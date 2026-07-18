import asyncio
import json
import time
from typing import Any, AsyncIterator, Callable

from starlette.responses import JSONResponse, StreamingResponse

from .config import client_protocol, endpoint_for_protocol, normalize_protocol, resolve_route
from .db import db, usage_tokens
from .http_client import upstream
from .protocol import (
    anthropic_chat_payload,
    anthropic_native_upstream_request,
    anthropic_response_from_chat,
    anthropic_sse_lines,
    chat_messages_from_response_output,
    chat_response_has_output,
    chat_stream_chunks,
    chat_to_responses_payload,
    merge_streamed_tool_name,
    normalize_upstream_chat_response,
    response_content_text,
    responses_chat_payload,
    responses_messages,
    responses_object,
    responses_output_items_from_chat,
    responses_output_text,
    responses_sse,
    responses_upstream_request,
    safe_int,
    uid,
    unwrap_upstream_error,
    upstream_request,
)


def api_error(message: str, status: int = 400, shape: str = "openai") -> JSONResponse:
    message = unwrap_upstream_error(message, str(message or ""))
    if shape == "anthropic":
        if status in {401, 403}:
            err_type = "authentication_error"
        elif status == 429:
            err_type = "rate_limit_error"
        elif status >= 500:
            err_type = "api_error"
        else:
            err_type = "invalid_request_error"
        return JSONResponse(
            {"type": "error", "error": {"type": err_type, "message": message}},
            status_code=status,
        )
    return JSONResponse({"error": {"message": message}}, status_code=status)


def protocol_mismatch_message(model: str, protocol: str, expected: str, endpoint: str) -> str:
    return (
        f"模型别名 {model} 配置为 {protocol} 协议，不能用于 {endpoint}；"
        f"请改用 {endpoint_for_protocol(protocol)}，或将该模型映射协议改为 {expected}"
    )


def require_client_protocol(model: str, protocol: str, expected: str, endpoint: str, shape: str = "openai"):
    if client_protocol(protocol) == expected:
        return None
    return api_error(protocol_mismatch_message(model, protocol, expected, endpoint), 400, shape)


def sse_headers() -> dict[str, str]:
    return {
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
        "Connection": "keep-alive",
    }


class StreamSession:
    """Ensure upstream stream context is always closed even if body is never read."""

    def __init__(self, stream_cm):
        self.stream_cm = stream_cm
        self.resp = None
        self._closed = False
        self._lock = asyncio.Lock()

    async def open(self):
        self.resp = await self.stream_cm.__aenter__()
        return self.resp

    async def close(self):
        async with self._lock:
            if self._closed:
                return
            self._closed = True
            try:
                await self.stream_cm.__aexit__(None, None, None)
            except Exception:
                pass

    def streaming_response(
        self,
        generate: Callable[[], AsyncIterator[bytes]],
        *,
        status_code: int = 200,
        media_type: str = "text/event-stream",
        headers: dict[str, str] | None = None,
    ) -> StreamingResponse:
        session = self

        async def guarded() -> AsyncIterator[bytes]:
            try:
                async for chunk in generate():
                    yield chunk
            finally:
                await session.close()

        return StreamingResponse(
            guarded(),
            media_type=media_type,
            status_code=status_code,
            headers=headers or sse_headers(),
        )


async def open_upstream_stream(url: str, headers: dict[str, str], payload: dict[str, Any]) -> StreamSession:
    stream_cm = await upstream.stream("POST", url, headers=headers, json=payload)
    session = StreamSession(stream_cm)
    await session.open()
    return session


async def proxy_openai_stream(
    url: str,
    headers: dict[str, str],
    payload: dict[str, Any],
    config: dict[str, Any],
    provider_id: str,
    model_alias: str,
    actual_model: str,
    request_body: str,
) -> StreamingResponse | JSONResponse:
    started = time.perf_counter()
    try:
        session = await open_upstream_stream(url, headers, payload)
    except Exception as exc:
        latency = int((time.perf_counter() - started) * 1000)
        await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model_alias, actual_model, True, 502, latency, request_body, "", str(exc))
        return api_error("请求后端失败: " + str(exc), 502)

    resp = session.resp
    status_code = resp.status_code
    if status_code < 200 or status_code >= 300:
        try:
            body = (await resp.aread()).decode("utf-8", errors="ignore")
        except Exception:
            body = ""
        await session.close()
        latency = int((time.perf_counter() - started) * 1000)
        message = unwrap_upstream_error(body, body or f"上游错误 {status_code}")
        await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model_alias, actual_model, True, status_code, latency, request_body, body, message)
        return api_error(message, status_code)

    async def generate() -> AsyncIterator[bytes]:
        response_body = ""
        sse_buffer = ""
        input_tokens = 0
        output_tokens = 0
        error = ""
        ok = True
        try:
            async for chunk in resp.aiter_bytes():
                if config.get("debug_requests") and len(response_body) < 2000:
                    response_body += chunk.decode("utf-8", errors="ignore")[: 2000 - len(response_body)]
                text = chunk.decode("utf-8", errors="ignore")
                sse_buffer += text
                while "\n" in sse_buffer:
                    line, sse_buffer = sse_buffer.split("\n", 1)
                    line = line.strip()
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        continue
                    try:
                        event = json.loads(data)
                    except Exception:
                        continue
                    if isinstance(event, dict) and "usage" in event:
                        input_tokens, output_tokens = usage_tokens(event.get("usage"))
                yield chunk
        except Exception as exc:
            ok = False
            error = str(exc)
            payload_err = json.dumps({"error": {"message": f"请求后端失败: {error}"}}, ensure_ascii=False)
            yield ("data: " + payload_err + "\n\n").encode("utf-8")
            yield b"data: [DONE]\n\n"
        finally:
            latency = int((time.perf_counter() - started) * 1000)
            await db.record_usage(
                config,
                provider_id,
                actual_model,
                input_tokens,
                output_tokens,
                latency,
                "ok" if ok else "error",
            )
            await db.log_request(
                config,
                provider_id,
                model_alias,
                actual_model,
                True,
                status_code if ok else 502,
                latency,
                request_body,
                response_body,
                error,
            )

    return session.streaming_response(generate, status_code=status_code)


async def proxy_raw_responses_stream(
    url: str,
    headers: dict[str, str],
    payload: dict[str, Any],
    config: dict[str, Any],
    provider_id: str,
    model_alias: str,
    actual_model: str,
    request_body: str,
    *,
    prior_messages: list[dict[str, Any]] | None = None,
    error_shape: str = "openai",
) -> StreamingResponse | JSONResponse:
    started = time.perf_counter()
    try:
        session = await open_upstream_stream(url, headers, payload)
    except Exception as exc:
        latency = int((time.perf_counter() - started) * 1000)
        await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model_alias, actual_model, True, 502, latency, request_body, "", str(exc))
        return api_error("请求后端失败: " + str(exc), 502, error_shape)

    resp = session.resp
    status_code = resp.status_code
    if status_code < 200 or status_code >= 300:
        try:
            body = (await resp.aread()).decode("utf-8", errors="ignore")
        except Exception:
            body = ""
        await session.close()
        latency = int((time.perf_counter() - started) * 1000)
        message = unwrap_upstream_error(body, body or f"上游错误 {status_code}")
        await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model_alias, actual_model, True, status_code, latency, request_body, body, message)
        return api_error(message, status_code, error_shape)

    async def generate() -> AsyncIterator[bytes]:
        response_body = ""
        sse_buffer = ""
        input_tokens = 0
        output_tokens = 0
        error = ""
        ok = True
        completed_response: dict[str, Any] | None = None
        try:
            async for chunk in resp.aiter_bytes():
                if config.get("debug_requests") and len(response_body) < 2000:
                    response_body += chunk.decode("utf-8", errors="ignore")[: 2000 - len(response_body)]
                text = chunk.decode("utf-8", errors="ignore")
                sse_buffer += text
                while "\n" in sse_buffer:
                    line, sse_buffer = sse_buffer.split("\n", 1)
                    line = line.strip()
                    if not line.startswith("data:") or line == "data: [DONE]":
                        continue
                    try:
                        event = json.loads(line[5:].strip())
                    except Exception:
                        continue
                    if isinstance(event, dict):
                        if event.get("type") == "response.completed" and isinstance(event.get("response"), dict):
                            completed_response = event["response"]
                        if isinstance(event.get("response"), dict) and "usage" in event["response"]:
                            input_tokens, output_tokens = usage_tokens(event["response"].get("usage"))
                        elif "usage" in event:
                            input_tokens, output_tokens = usage_tokens(event.get("usage"))
                yield chunk
        except Exception as exc:
            ok = False
            error = str(exc)
            yield responses_sse(
                "response.failed",
                {"response": responses_object(uid("resp_"), actual_model, "failed", [], 0, 0, f"请求后端失败: {error}")},
            ).encode()
            yield b"data: [DONE]\n\n"
        finally:
            if ok and completed_response and prior_messages is not None:
                try:
                    response_id = str(completed_response.get("id") or uid("resp_"))
                    chat = normalize_upstream_chat_response(completed_response, {"type": "responses"}, actual_model)
                    out_text = responses_output_text(chat)
                    output = responses_output_items_from_chat(chat, uid("msg_"), out_text)
                    await db.save_response_state(
                        response_id,
                        list(prior_messages) + chat_messages_from_response_output(output),
                    )
                except Exception:
                    pass
            latency = int((time.perf_counter() - started) * 1000)
            await db.record_usage(config, provider_id, actual_model, input_tokens, output_tokens, latency, "ok" if ok else "error")
            await db.log_request(config, provider_id, model_alias, actual_model, True, status_code if ok else 502, latency, request_body, response_body, error)

    return session.streaming_response(generate, status_code=status_code)


async def proxy_raw_anthropic_stream(
    url: str,
    headers: dict[str, str],
    payload: dict[str, Any],
    config: dict[str, Any],
    provider_id: str,
    model_alias: str,
    actual_model: str,
    request_body: str,
) -> StreamingResponse | JSONResponse:
    started = time.perf_counter()
    try:
        session = await open_upstream_stream(url, headers, payload)
    except Exception as exc:
        latency = int((time.perf_counter() - started) * 1000)
        await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model_alias, actual_model, True, 502, latency, request_body, "", str(exc))
        return api_error("请求后端失败: " + str(exc), 502, "anthropic")

    resp = session.resp
    status_code = resp.status_code
    if status_code < 200 or status_code >= 300:
        try:
            body = (await resp.aread()).decode("utf-8", errors="ignore")
        except Exception:
            body = ""
        await session.close()
        latency = int((time.perf_counter() - started) * 1000)
        message = unwrap_upstream_error(body, body or f"上游错误 {status_code}")
        await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model_alias, actual_model, True, status_code, latency, request_body, body, message)
        return api_error(message, status_code, "anthropic")

    async def generate() -> AsyncIterator[bytes]:
        response_body = ""
        sse_buffer = ""
        input_tokens = 0
        output_tokens = 0
        error = ""
        ok = True
        try:
            async for chunk in resp.aiter_bytes():
                if config.get("debug_requests") and len(response_body) < 2000:
                    response_body += chunk.decode("utf-8", errors="ignore")[: 2000 - len(response_body)]
                text = chunk.decode("utf-8", errors="ignore")
                sse_buffer += text
                while "\n" in sse_buffer:
                    line, sse_buffer = sse_buffer.split("\n", 1)
                    line = line.strip()
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if not data:
                        continue
                    try:
                        event = json.loads(data)
                    except Exception:
                        continue
                    if not isinstance(event, dict):
                        continue
                    # Anthropic SSE usage typically appears on message_start / message_delta
                    if event.get("type") == "message_start" and isinstance(event.get("message"), dict):
                        usage = event["message"].get("usage") or {}
                        input_tokens = safe_int(usage.get("input_tokens") or input_tokens or 0, input_tokens)
                        output_tokens = safe_int(usage.get("output_tokens") or output_tokens or 0, output_tokens)
                    if event.get("type") == "message_delta":
                        usage = event.get("usage") or {}
                        if "output_tokens" in usage:
                            output_tokens = safe_int(usage.get("output_tokens") or output_tokens or 0, output_tokens)
                        if "input_tokens" in usage:
                            input_tokens = safe_int(usage.get("input_tokens") or input_tokens or 0, input_tokens)
                yield chunk
        except Exception as exc:
            ok = False
            error = str(exc)
            yield (
                "event: error\n"
                + "data: "
                + json.dumps({"type": "error", "error": {"type": "api_error", "message": error}}, ensure_ascii=False)
                + "\n\n"
            ).encode()
        finally:
            latency = int((time.perf_counter() - started) * 1000)
            await db.record_usage(config, provider_id, actual_model, input_tokens, output_tokens, latency, "ok" if ok else "error")
            await db.log_request(config, provider_id, model_alias, actual_model, True, status_code if ok else 502, latency, request_body, response_body, error)

    return session.streaming_response(generate, status_code=status_code)


async def proxy_chat_to_responses_stream(
    url: str,
    headers: dict[str, str],
    payload: dict[str, Any],
    config: dict[str, Any],
    provider_id: str,
    model_alias: str,
    actual_model: str,
    request_body: str,
    messages: list[dict[str, Any]],
) -> StreamingResponse | JSONResponse:
    response_id = uid("resp_")
    message_id = uid("msg_")
    started = time.perf_counter()
    try:
        session = await open_upstream_stream(url, headers, payload)
    except Exception as exc:
        latency = int((time.perf_counter() - started) * 1000)
        await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model_alias, actual_model, True, 502, latency, request_body, "", str(exc))
        return api_error("请求后端失败: " + str(exc), 502)

    resp = session.resp
    status_code = resp.status_code
    if status_code < 200 or status_code >= 300:
        try:
            body = (await resp.aread()).decode("utf-8", errors="ignore")
        except Exception:
            body = ""
        await session.close()
        latency = int((time.perf_counter() - started) * 1000)
        message = unwrap_upstream_error(body, body or f"上游错误 {status_code}")
        await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model_alias, actual_model, True, status_code, latency, request_body, body, message)
        return api_error(message, status_code)

    async def generate() -> AsyncIterator[bytes]:
        raw_response = ""
        buffer = ""
        text = ""
        message_started = False
        message_output_index = None
        next_output_index = 0
        tool_calls: dict[int, dict[str, Any]] = {}
        input_tokens = 0
        output_tokens = 0
        error = ""
        try:
            yield responses_sse(
                "response.created",
                {"response": responses_object(response_id, actual_model, "in_progress", [], 0, 0)},
            ).encode()
            yield responses_sse(
                "response.in_progress",
                {"response": responses_object(response_id, actual_model, "in_progress", [], 0, 0)},
            ).encode()
            async for chunk in resp.aiter_bytes():
                if config.get("debug_requests") and len(raw_response) < 2000:
                    raw_response += chunk.decode("utf-8", errors="ignore")[: 2000 - len(raw_response)]
                buffer += chunk.decode("utf-8", errors="ignore")
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if not line.startswith("data:") or line == "data: [DONE]":
                        continue
                    try:
                        event = json.loads(line[5:].strip())
                    except Exception:
                        continue
                    if not isinstance(event, dict):
                        continue
                    if "usage" in event:
                        input_tokens, output_tokens = usage_tokens(event.get("usage"))
                    delta = (((event.get("choices") or [{}])[0]).get("delta") or {})
                    if not isinstance(delta, dict):
                        delta = {}
                    delta_text = response_content_text(delta.get("content"))
                    if delta_text:
                        if not message_started:
                            message_started = True
                            message_output_index = next_output_index
                            next_output_index += 1
                            item = {
                                "id": message_id,
                                "type": "message",
                                "status": "in_progress",
                                "role": "assistant",
                                "content": [],
                            }
                            yield responses_sse(
                                "response.output_item.added",
                                {"response_id": response_id, "output_index": message_output_index, "item": item},
                            ).encode()
                            yield responses_sse(
                                "response.content_part.added",
                                {
                                    "response_id": response_id,
                                    "item_id": message_id,
                                    "output_index": message_output_index,
                                    "content_index": 0,
                                    "part": {"type": "output_text", "text": "", "annotations": []},
                                },
                            ).encode()
                        text += delta_text
                        yield responses_sse(
                            "response.output_text.delta",
                            {
                                "response_id": response_id,
                                "item_id": message_id,
                                "output_index": message_output_index,
                                "content_index": 0,
                                "delta": delta_text,
                                "logprobs": [],
                            },
                        ).encode()
                    for tool_delta in delta.get("tool_calls") or []:
                        if not isinstance(tool_delta, dict):
                            continue
                        index = safe_int(tool_delta.get("index") or 0, 0)
                        function = tool_delta.get("function") if isinstance(tool_delta.get("function"), dict) else {}
                        is_new = index not in tool_calls
                        if is_new:
                            tool_calls[index] = {
                                "id": uid("fc_"),
                                "call_id": tool_delta.get("id") or uid("call_"),
                                "name": "",
                                "arguments": "",
                                "output_index": next_output_index,
                            }
                            next_output_index += 1
                        if function.get("name"):
                            tool_calls[index]["name"] = merge_streamed_tool_name(
                                tool_calls[index]["name"], function.get("name") or ""
                            )
                        if is_new:
                            item = {
                                "id": tool_calls[index]["id"],
                                "type": "function_call",
                                "status": "in_progress",
                                "call_id": tool_calls[index]["call_id"],
                                "name": tool_calls[index]["name"],
                                "arguments": "",
                            }
                            yield responses_sse(
                                "response.output_item.added",
                                {
                                    "response_id": response_id,
                                    "output_index": tool_calls[index]["output_index"],
                                    "item": item,
                                },
                            ).encode()
                        if tool_delta.get("id"):
                            tool_calls[index]["call_id"] = tool_delta["id"]
                        arguments_delta = str(function.get("arguments") or "")
                        if arguments_delta:
                            tool_calls[index]["arguments"] += arguments_delta
                            yield responses_sse(
                                "response.function_call_arguments.delta",
                                {
                                    "response_id": response_id,
                                    "item_id": tool_calls[index]["id"],
                                    "output_index": tool_calls[index]["output_index"],
                                    "delta": arguments_delta,
                                },
                            ).encode()

            output: dict[int, dict[str, Any]] = {}
            if message_started:
                yield responses_sse(
                    "response.output_text.done",
                    {
                        "response_id": response_id,
                        "item_id": message_id,
                        "output_index": message_output_index,
                        "content_index": 0,
                        "text": text,
                        "logprobs": [],
                    },
                ).encode()
                part = {"type": "output_text", "text": text, "annotations": []}
                yield responses_sse(
                    "response.content_part.done",
                    {
                        "response_id": response_id,
                        "item_id": message_id,
                        "output_index": message_output_index,
                        "content_index": 0,
                        "part": part,
                    },
                ).encode()
                item = {
                    "id": message_id,
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [part],
                }
                yield responses_sse(
                    "response.output_item.done",
                    {"response_id": response_id, "output_index": message_output_index, "item": item},
                ).encode()
                output[message_output_index] = item
            for tool in tool_calls.values():
                yield responses_sse(
                    "response.function_call_arguments.done",
                    {
                        "response_id": response_id,
                        "item_id": tool["id"],
                        "output_index": tool["output_index"],
                        "arguments": tool["arguments"],
                    },
                ).encode()
                item = {
                    "id": tool["id"],
                    "type": "function_call",
                    "status": "completed",
                    "call_id": tool["call_id"],
                    "name": tool["name"],
                    "arguments": tool["arguments"],
                }
                yield responses_sse(
                    "response.output_item.done",
                    {"response_id": response_id, "output_index": tool["output_index"], "item": item},
                ).encode()
                output[tool["output_index"]] = item
            ordered = [output[i] for i in sorted(output)]
            if not ordered:
                message = "上游流式响应没有可解析的 assistant 内容或工具调用"
                latency = int((time.perf_counter() - started) * 1000)
                await db.record_usage(config, provider_id, actual_model, input_tokens, output_tokens, latency, "error")
                await db.log_request(config, provider_id, model_alias, actual_model, True, 502, latency, request_body, raw_response, message)
                yield responses_sse(
                    "response.failed",
                    {"response": responses_object(response_id, actual_model, "failed", [], 0, 0, message)},
                ).encode()
                yield b"data: [DONE]\n\n"
                return
            await db.save_response_state(response_id, messages + chat_messages_from_response_output(ordered))
            latency = int((time.perf_counter() - started) * 1000)
            await db.record_usage(config, provider_id, actual_model, input_tokens, output_tokens, latency, "ok")
            await db.log_request(config, provider_id, model_alias, actual_model, True, status_code, latency, request_body, raw_response, "")
            yield responses_sse(
                "response.completed",
                {
                    "response": responses_object(
                        response_id, actual_model, "completed", ordered, input_tokens, output_tokens
                    )
                },
            ).encode()
            yield b"data: [DONE]\n\n"
        except Exception as exc:
            error = str(exc)
            latency = int((time.perf_counter() - started) * 1000)
            await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
            await db.log_request(config, provider_id, model_alias, actual_model, True, 502, latency, request_body, raw_response, error)
            yield responses_sse(
                "response.failed",
                {"response": responses_object(response_id, actual_model, "failed", [], 0, 0, f"请求后端失败: {error}")},
            ).encode()
            yield b"data: [DONE]\n\n"

    return session.streaming_response(generate, status_code=200)


async def proxy_openai_to_anthropic_stream(
    url: str,
    headers: dict[str, str],
    payload: dict[str, Any],
    config: dict[str, Any],
    provider_id: str,
    model_alias: str,
    actual_model: str,
    request_body: str,
) -> StreamingResponse | JSONResponse:
    started = time.perf_counter()
    try:
        session = await open_upstream_stream(url, headers, payload)
    except Exception as exc:
        latency = int((time.perf_counter() - started) * 1000)
        await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model_alias, actual_model, True, 502, latency, request_body, "", str(exc))
        return api_error("请求后端失败: " + str(exc), 502, "anthropic")

    resp = session.resp
    status_code = resp.status_code
    if status_code < 200 or status_code >= 300:
        try:
            body = (await resp.aread()).decode("utf-8", errors="ignore")
        except Exception:
            body = ""
        await session.close()
        latency = int((time.perf_counter() - started) * 1000)
        message = unwrap_upstream_error(body, body or f"上游错误 {status_code}")
        await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model_alias, actual_model, True, status_code, latency, request_body, body, message)
        return api_error(message, status_code, "anthropic")

    message_id = uid("msg_")

    async def generate() -> AsyncIterator[bytes]:
        buffer = ""
        text = ""
        tool_calls: dict[int, dict[str, Any]] = {}
        input_tokens = 0
        output_tokens = 0
        raw_response = ""
        error = ""
        next_block_index = 0
        text_block_index: int | None = None
        try:
            start_msg = {
                "id": message_id,
                "type": "message",
                "role": "assistant",
                "model": actual_model,
                "content": [],
                "stop_reason": None,
                "stop_sequence": None,
                "usage": {"input_tokens": 0, "output_tokens": 0},
            }
            yield f"event: message_start\ndata: {json.dumps({'type':'message_start','message':start_msg}, ensure_ascii=False)}\n\n".encode()
            async for chunk in resp.aiter_bytes():
                if config.get("debug_requests") and len(raw_response) < 2000:
                    raw_response += chunk.decode("utf-8", errors="ignore")[: 2000 - len(raw_response)]
                buffer += chunk.decode("utf-8", errors="ignore")
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if not line.startswith("data:") or line == "data: [DONE]":
                        continue
                    try:
                        event = json.loads(line[5:].strip())
                    except Exception:
                        continue
                    if not isinstance(event, dict):
                        continue
                    if "usage" in event:
                        input_tokens, output_tokens = usage_tokens(event.get("usage"))
                    delta = (((event.get("choices") or [{}])[0]).get("delta") or {})
                    if not isinstance(delta, dict):
                        delta = {}
                    delta_text = response_content_text(delta.get("content"))
                    if delta_text:
                        if text_block_index is None:
                            text_block_index = next_block_index
                            next_block_index += 1
                            yield (
                                "event: content_block_start\ndata: "
                                + json.dumps(
                                    {
                                        "type": "content_block_start",
                                        "index": text_block_index,
                                        "content_block": {"type": "text", "text": ""},
                                    },
                                    ensure_ascii=False,
                                )
                                + "\n\n"
                            ).encode()
                        text += delta_text
                        yield (
                            "event: content_block_delta\ndata: "
                            + json.dumps(
                                {
                                    "type": "content_block_delta",
                                    "index": text_block_index,
                                    "delta": {"type": "text_delta", "text": delta_text},
                                },
                                ensure_ascii=False,
                            )
                            + "\n\n"
                        ).encode()
                    for tool_delta in delta.get("tool_calls") or []:
                        if not isinstance(tool_delta, dict):
                            continue
                        index = safe_int(tool_delta.get("index") or 0, 0)
                        function = tool_delta.get("function") if isinstance(tool_delta.get("function"), dict) else {}
                        if index not in tool_calls:
                            tool_calls[index] = {
                                "id": tool_delta.get("id") or uid("toolu_"),
                                "name": "",
                                "arguments": "",
                                "started": False,
                                "block_index": None,
                            }
                        if function.get("name"):
                            tool_calls[index]["name"] = merge_streamed_tool_name(
                                tool_calls[index]["name"], function.get("name") or ""
                            )
                        if tool_delta.get("id"):
                            tool_calls[index]["id"] = tool_delta["id"]
                        if not tool_calls[index]["started"] and tool_calls[index]["name"]:
                            tool_calls[index]["started"] = True
                            tool_calls[index]["block_index"] = next_block_index
                            next_block_index += 1
                            start_block = {
                                "type": "tool_use",
                                "id": tool_calls[index]["id"],
                                "name": tool_calls[index]["name"],
                                "input": {},
                            }
                            yield (
                                "event: content_block_start\ndata: "
                                + json.dumps(
                                    {
                                        "type": "content_block_start",
                                        "index": tool_calls[index]["block_index"],
                                        "content_block": start_block,
                                    },
                                    ensure_ascii=False,
                                )
                                + "\n\n"
                            ).encode()
                            if tool_calls[index]["arguments"]:
                                yield (
                                    "event: content_block_delta\ndata: "
                                    + json.dumps(
                                        {
                                            "type": "content_block_delta",
                                            "index": tool_calls[index]["block_index"],
                                            "delta": {
                                                "type": "input_json_delta",
                                                "partial_json": tool_calls[index]["arguments"],
                                            },
                                        },
                                        ensure_ascii=False,
                                    )
                                    + "\n\n"
                                ).encode()
                        args_delta = str(function.get("arguments") or "")
                        if args_delta:
                            tool_calls[index]["arguments"] += args_delta
                            if tool_calls[index].get("block_index") is not None:
                                yield (
                                    "event: content_block_delta\ndata: "
                                    + json.dumps(
                                        {
                                            "type": "content_block_delta",
                                            "index": tool_calls[index]["block_index"],
                                            "delta": {
                                                "type": "input_json_delta",
                                                "partial_json": args_delta,
                                            },
                                        },
                                        ensure_ascii=False,
                                    )
                                    + "\n\n"
                                ).encode()

            if text_block_index is not None:
                yield (
                    "event: content_block_stop\ndata: "
                    + json.dumps({"type": "content_block_stop", "index": text_block_index}, ensure_ascii=False)
                    + "\n\n"
                ).encode()
            for tool in sorted(
                (t for t in tool_calls.values() if t.get("started") and t.get("block_index") is not None),
                key=lambda t: int(t["block_index"]),
            ):
                yield (
                    "event: content_block_stop\ndata: "
                    + json.dumps({"type": "content_block_stop", "index": tool["block_index"]}, ensure_ascii=False)
                    + "\n\n"
                ).encode()
            stop_reason = "tool_use" if any(t.get("started") for t in tool_calls.values()) else "end_turn"
            yield (
                "event: message_delta\ndata: "
                + json.dumps(
                    {
                        "type": "message_delta",
                        "delta": {"stop_reason": stop_reason, "stop_sequence": None},
                        "usage": {"output_tokens": output_tokens},
                    },
                    ensure_ascii=False,
                )
                + "\n\n"
            ).encode()
            yield (
                "event: message_stop\ndata: "
                + json.dumps({"type": "message_stop"}, ensure_ascii=False)
                + "\n\n"
            ).encode()
            latency = int((time.perf_counter() - started) * 1000)
            await db.record_usage(config, provider_id, actual_model, input_tokens, output_tokens, latency, "ok")
            await db.log_request(
                config,
                provider_id,
                model_alias,
                actual_model,
                True,
                status_code,
                latency,
                request_body,
                raw_response,
                "",
            )
        except Exception as exc:
            error = str(exc)
            latency = int((time.perf_counter() - started) * 1000)
            await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
            await db.log_request(
                config,
                provider_id,
                model_alias,
                actual_model,
                True,
                502,
                latency,
                request_body,
                raw_response,
                error,
            )
            yield (
                "event: error\ndata: "
                + json.dumps({"type": "error", "error": {"type": "api_error", "message": error}}, ensure_ascii=False)
                + "\n\n"
            ).encode()

    return session.streaming_response(generate, status_code=200)


async def nonstream_upstream(
    provider: dict[str, Any],
    actual_model: str,
    chat_body: dict[str, Any],
    protocol: str = "",
) -> tuple[int, dict[str, Any] | None, str, str]:
    url, headers, payload = upstream_request(provider, actual_model, chat_body, protocol=protocol)
    try:
        resp = await upstream.request("POST", url, headers=headers, json=payload)
    except Exception as exc:
        return 502, None, "", str(exc)
    text = resp.text
    try:
        data = resp.json()
    except Exception:
        data = None
    return resp.status_code, data if isinstance(data, dict) else None, text, ""


async def handle_chat_request(config: dict[str, Any], body: dict[str, Any]):
    model = body.get("model") or ""
    request_body = json.dumps(body, ensure_ascii=False)
    provider_id, provider, actual_model, protocol, error = resolve_route(config, model)
    if error:
        return api_error(error)
    mismatch = require_client_protocol(model, protocol, "openai", "/v1/chat/completions")
    if mismatch:
        return mismatch
    upstream_protocol = normalize_protocol("", provider)
    upstream_body = dict(body)
    if body.get("stream") and upstream_protocol != "openai":
        upstream_body["stream"] = False
    url, headers, payload = upstream_request(provider, actual_model, upstream_body)
    if body.get("stream") and upstream_protocol == "openai":
        return await proxy_openai_stream(
            url, headers, payload, config, provider_id, model, actual_model, request_body
        )
    started = time.perf_counter()
    status, upstream_result, response_text, curl_error = await nonstream_upstream(provider, actual_model, upstream_body)
    latency = int((time.perf_counter() - started) * 1000)
    if curl_error:
        await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model, actual_model, False, 502, latency, request_body, "", curl_error)
        return api_error("请求后端失败: " + curl_error, 502)
    if status < 200 or status >= 300:
        message = unwrap_upstream_error(upstream_result or response_text, response_text or f"上游错误 {status}")
        await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model, actual_model, False, status, latency, request_body, response_text, message)
        return api_error(message, status)
    if upstream_result is None:
        await db.record_usage(config, provider_id, actual_model, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model, actual_model, False, 502, latency, request_body, response_text, "上游返回了无效 JSON")
        return api_error("上游返回了无效 JSON", 502)
    result = normalize_upstream_chat_response(upstream_result, provider, actual_model)
    input_tokens, output_tokens = usage_tokens(result.get("usage"))
    if not chat_response_has_output(result):
        message = "上游响应没有 assistant 内容或工具调用"
        await db.record_usage(config, provider_id, actual_model, input_tokens, output_tokens, latency, "error")
        await db.log_request(config, provider_id, model, actual_model, False, 502, latency, request_body, response_text, message)
        return api_error(message, 502)
    await db.record_usage(config, provider_id, actual_model, input_tokens, output_tokens, latency, "ok")
    await db.log_request(config, provider_id, model, actual_model, False, status, latency, request_body, response_text, "")
    if body.get("stream"):
        async def generate():
            for chunk in chat_stream_chunks(result, actual_model):
                yield chunk.encode("utf-8")
        return StreamingResponse(generate(), media_type="text/event-stream", status_code=200, headers=sse_headers())
    return JSONResponse(result)


async def handle_responses_request(config: dict[str, Any], body: dict[str, Any]):
    stream = bool(body.get("stream"))
    model = body.get("model") or ""
    request_body = json.dumps(body, ensure_ascii=False)
    previous_id = str(body.get("previous_response_id") or "")
    previous_messages = await db.load_response_state(previous_id)
    if previous_id and previous_messages is None:
        return api_error("previous_response_id 不存在或已过期", 400)

    provider_id, provider, actual, protocol, error = resolve_route(config, model)
    if error:
        return api_error(error)
    mismatch = require_client_protocol(model, protocol, "responses", "/v1/responses")
    if mismatch:
        return mismatch

    upstream_protocol = normalize_protocol("", provider)
    messages = list(previous_messages or []) + responses_messages(body)

    if upstream_protocol == "responses":
        native_body = dict(body)
        native_body["model"] = actual
        if previous_messages is not None and previous_id:
            chat_body = responses_chat_payload(body, messages)
            native_body = chat_to_responses_payload(chat_body)
            native_body["model"] = actual
            native_body["stream"] = stream
        url, headers, payload = responses_upstream_request(provider, actual, native_body)
        if stream:
            return await proxy_raw_responses_stream(
                url,
                headers,
                payload,
                config,
                provider_id,
                model,
                actual,
                request_body,
                prior_messages=messages,
            )
        started = time.perf_counter()
        try:
            resp = await upstream.request("POST", url, headers=headers, json=payload)
        except Exception as exc:
            latency = int((time.perf_counter() - started) * 1000)
            await db.record_usage(config, provider_id, actual, 0, 0, latency, "error")
            await db.log_request(config, provider_id, model, actual, False, 502, latency, request_body, "", str(exc))
            return api_error("请求后端失败: " + str(exc), 502)
        latency = int((time.perf_counter() - started) * 1000)
        text = resp.text
        try:
            data = resp.json()
        except Exception:
            data = None
        if resp.status_code < 200 or resp.status_code >= 300:
            message = unwrap_upstream_error(data or text, text or f"上游错误 {resp.status_code}")
            await db.record_usage(config, provider_id, actual, 0, 0, latency, "error")
            await db.log_request(config, provider_id, model, actual, False, resp.status_code, latency, request_body, text, message)
            return api_error(message, resp.status_code)
        if not isinstance(data, dict):
            await db.record_usage(config, provider_id, actual, 0, 0, latency, "error")
            await db.log_request(config, provider_id, model, actual, False, 502, latency, request_body, text, "上游返回了无效 JSON")
            return api_error("上游返回了无效 JSON", 502)
        input_tokens, output_tokens = usage_tokens(data.get("usage"))
        response_id = str(data.get("id") or uid("resp_"))
        chat = normalize_upstream_chat_response(data, provider, actual)
        out_text = responses_output_text(chat)
        output = responses_output_items_from_chat(chat, uid("msg_"), out_text)
        await db.save_response_state(response_id, messages + chat_messages_from_response_output(output))
        await db.record_usage(config, provider_id, actual, input_tokens, output_tokens, latency, "ok")
        await db.log_request(config, provider_id, model, actual, False, resp.status_code, latency, request_body, text, "")
        return JSONResponse(data)

    chat_body = responses_chat_payload(body, messages)
    chat_body["stream"] = stream and upstream_protocol == "openai"
    if chat_body["stream"]:
        chat_body["stream_options"] = {"include_usage": True}
    url, headers, payload = upstream_request(provider, actual, chat_body)
    if stream and upstream_protocol == "openai":
        return await proxy_chat_to_responses_stream(
            url, headers, payload, config, provider_id, model, actual, request_body, messages
        )

    response_id = uid("resp_")
    message_id = uid("msg_")
    started = time.perf_counter()
    status, upstream_result, response_text, curl_error = await nonstream_upstream(provider, actual, chat_body)
    latency = int((time.perf_counter() - started) * 1000)

    async def failed_stream(message: str, code: int = 200):
        yield responses_sse(
            "response.created",
            {"response": responses_object(response_id, actual, "in_progress", [], 0, 0)},
        ).encode()
        yield responses_sse(
            "response.failed",
            {"response": responses_object(response_id, actual, "failed", [], 0, 0, message)},
        ).encode()
        yield b"data: [DONE]\n\n"

    if curl_error:
        await db.record_usage(config, provider_id, actual, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model, actual, stream, 502, latency, request_body, "", curl_error)
        if stream:
            return StreamingResponse(failed_stream("请求后端失败: " + curl_error), media_type="text/event-stream", status_code=200, headers=sse_headers())
        return api_error("请求后端失败: " + curl_error, 502)
    if status < 200 or status >= 300:
        message = unwrap_upstream_error(upstream_result or response_text, response_text or f"上游错误 {status}")
        await db.record_usage(config, provider_id, actual, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model, actual, stream, status, latency, request_body, response_text, message)
        if stream:
            return StreamingResponse(failed_stream(message), media_type="text/event-stream", status_code=200, headers=sse_headers())
        return api_error(message, status)
    if upstream_result is None:
        await db.record_usage(config, provider_id, actual, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model, actual, stream, 502, latency, request_body, response_text, "上游返回了无效 JSON")
        if stream:
            return StreamingResponse(failed_stream("上游返回了无效 JSON"), media_type="text/event-stream", status_code=200, headers=sse_headers())
        return api_error("上游返回了无效 JSON", 502)
    chat = normalize_upstream_chat_response(upstream_result, provider, actual)
    text = responses_output_text(chat)
    if text == "":
        for part in chat.get("content") or []:
            if isinstance(part, dict) and "text" in part:
                text += str(part.get("text") or "")
    input_tokens, output_tokens = usage_tokens(chat.get("usage"))
    if not chat_response_has_output(chat, text):
        message = "上游响应没有 assistant 内容或工具调用"
        await db.record_usage(config, provider_id, actual, input_tokens, output_tokens, latency, "error")
        await db.log_request(config, provider_id, model, actual, stream, 502, latency, request_body, response_text, message)
        if stream:
            return StreamingResponse(failed_stream(message), media_type="text/event-stream", status_code=200, headers=sse_headers())
        return api_error(message, 502)
    await db.record_usage(config, provider_id, actual, input_tokens, output_tokens, latency, "ok")
    await db.log_request(config, provider_id, model, actual, stream, status, latency, request_body, response_text, "")
    output = responses_output_items_from_chat(chat, message_id, text)
    await db.save_response_state(response_id, messages + chat_messages_from_response_output(output))
    if stream:
        async def generate():
            yield responses_sse(
                "response.created",
                {"response": responses_object(response_id, actual, "in_progress", [], 0, 0)},
            ).encode()
            yield responses_sse(
                "response.in_progress",
                {"response": responses_object(response_id, actual, "in_progress", [], 0, 0)},
            ).encode()
            for index, item in enumerate(output):
                if item.get("type") == "message":
                    item_id = item.get("id") or message_id
                    text_value = response_content_text(item.get("content"))
                    yield responses_sse(
                        "response.output_item.added",
                        {
                            "response_id": response_id,
                            "output_index": index,
                            "item": {
                                "id": item_id,
                                "type": "message",
                                "status": "in_progress",
                                "role": "assistant",
                                "content": [],
                            },
                        },
                    ).encode()
                    yield responses_sse(
                        "response.content_part.added",
                        {
                            "response_id": response_id,
                            "item_id": item_id,
                            "output_index": index,
                            "content_index": 0,
                            "part": {"type": "output_text", "text": "", "annotations": []},
                        },
                    ).encode()
                    if text_value:
                        yield responses_sse(
                            "response.output_text.delta",
                            {
                                "response_id": response_id,
                                "item_id": item_id,
                                "output_index": index,
                                "content_index": 0,
                                "delta": text_value,
                                "logprobs": [],
                            },
                        ).encode()
                    yield responses_sse(
                        "response.output_text.done",
                        {
                            "response_id": response_id,
                            "item_id": item_id,
                            "output_index": index,
                            "content_index": 0,
                            "text": text_value,
                            "logprobs": [],
                        },
                    ).encode()
                    part = {"type": "output_text", "text": text_value, "annotations": []}
                    yield responses_sse(
                        "response.content_part.done",
                        {
                            "response_id": response_id,
                            "item_id": item_id,
                            "output_index": index,
                            "content_index": 0,
                            "part": part,
                        },
                    ).encode()
                    done = dict(item)
                    done["id"] = item_id
                    done["status"] = "completed"
                    done["content"] = [part]
                    yield responses_sse(
                        "response.output_item.done",
                        {"response_id": response_id, "output_index": index, "item": done},
                    ).encode()
                elif item.get("type") == "function_call":
                    item_id = item.get("id") or uid("fc_")
                    arguments = str(item.get("arguments") or "")
                    added = dict(item)
                    added["id"] = item_id
                    added["status"] = "in_progress"
                    added["arguments"] = ""
                    yield responses_sse(
                        "response.output_item.added",
                        {"response_id": response_id, "output_index": index, "item": added},
                    ).encode()
                    if arguments:
                        yield responses_sse(
                            "response.function_call_arguments.delta",
                            {
                                "response_id": response_id,
                                "item_id": item_id,
                                "output_index": index,
                                "delta": arguments,
                            },
                        ).encode()
                    yield responses_sse(
                        "response.function_call_arguments.done",
                        {
                            "response_id": response_id,
                            "item_id": item_id,
                            "output_index": index,
                            "arguments": arguments,
                        },
                    ).encode()
                    done = dict(item)
                    done["id"] = item_id
                    done["status"] = "completed"
                    done["arguments"] = arguments
                    yield responses_sse(
                        "response.output_item.done",
                        {"response_id": response_id, "output_index": index, "item": done},
                    ).encode()
            yield responses_sse(
                "response.completed",
                {
                    "response": responses_object(
                        response_id, actual, "completed", output, input_tokens, output_tokens
                    )
                },
            ).encode()
            yield b"data: [DONE]\n\n"

        return StreamingResponse(generate(), media_type="text/event-stream", status_code=200, headers=sse_headers())
    return JSONResponse(responses_object(response_id, actual, "completed", output, input_tokens, output_tokens))


async def handle_anthropic_request(config: dict[str, Any], body: dict[str, Any]):
    request_body = json.dumps(body, ensure_ascii=False)
    model = body.get("model") or ""
    provider_id, provider, actual, protocol, error = resolve_route(config, model)
    if error:
        return api_error(error, 400, "anthropic")
    mismatch = require_client_protocol(model, protocol, "anthropic", "/v1/messages", "anthropic")
    if mismatch:
        return mismatch

    upstream_protocol = normalize_protocol("", provider)
    want_stream = bool(body.get("stream"))

    # Native anthropic upstream: passthrough request body, only rewrite model.
    if upstream_protocol == "anthropic":
        native = dict(body)
        native["model"] = actual
        url, headers, payload = anthropic_native_upstream_request(provider, actual, native)
        if want_stream:
            payload["stream"] = True
            return await proxy_raw_anthropic_stream(
                url, headers, payload, config, provider_id, model, actual, request_body
            )
        started = time.perf_counter()
        try:
            resp = await upstream.request("POST", url, headers=headers, json=payload)
        except Exception as exc:
            latency = int((time.perf_counter() - started) * 1000)
            await db.record_usage(config, provider_id, actual, 0, 0, latency, "error")
            await db.log_request(config, provider_id, model, actual, False, 502, latency, request_body, "", str(exc))
            return api_error("请求后端失败: " + str(exc), 502, "anthropic")
        latency = int((time.perf_counter() - started) * 1000)
        text = resp.text
        try:
            data = resp.json()
        except Exception:
            data = None
        if resp.status_code < 200 or resp.status_code >= 300:
            message = unwrap_upstream_error(data or text, text or f"上游错误 {resp.status_code}")
            await db.record_usage(config, provider_id, actual, 0, 0, latency, "error")
            await db.log_request(config, provider_id, model, actual, False, resp.status_code, latency, request_body, text, message)
            return api_error(message, resp.status_code, "anthropic")
        if not isinstance(data, dict):
            await db.record_usage(config, provider_id, actual, 0, 0, latency, "error")
            await db.log_request(config, provider_id, model, actual, False, 502, latency, request_body, text, "上游返回了无效 JSON")
            return api_error("上游返回了无效 JSON", 502, "anthropic")
        input_tokens, output_tokens = usage_tokens(data.get("usage"))
        await db.record_usage(config, provider_id, actual, input_tokens, output_tokens, latency, "ok")
        await db.log_request(config, provider_id, model, actual, False, resp.status_code, latency, request_body, text, "")
        return JSONResponse(data)

    # Non-anthropic upstream: convert via chat intermediate.
    chat = anthropic_chat_payload(body)

    if want_stream and upstream_protocol == "openai":
        stream_chat = dict(chat)
        stream_chat["stream"] = True
        stream_chat["stream_options"] = {"include_usage": True}
        url, headers, payload = upstream_request(provider, actual, stream_chat)
        return await proxy_openai_to_anthropic_stream(
            url, headers, payload, config, provider_id, model, actual, request_body
        )

    started = time.perf_counter()
    status, upstream_result, response_text, curl_error = await nonstream_upstream(provider, actual, chat)
    latency = int((time.perf_counter() - started) * 1000)
    if curl_error:
        await db.record_usage(config, provider_id, actual, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model, actual, False, 502, latency, request_body, "", curl_error)
        return api_error("请求后端失败: " + curl_error, 502, "anthropic")
    if status < 200 or status >= 300:
        message = unwrap_upstream_error(upstream_result or response_text, response_text or f"上游错误 {status}")
        await db.record_usage(config, provider_id, actual, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model, actual, False, status, latency, request_body, response_text, message)
        return api_error(message, status, "anthropic")
    if upstream_result is None:
        await db.record_usage(config, provider_id, actual, 0, 0, latency, "error")
        await db.log_request(config, provider_id, model, actual, False, 502, latency, request_body, response_text, "上游返回了无效 JSON")
        return api_error("上游返回了无效 JSON", 502, "anthropic")
    chat_response = normalize_upstream_chat_response(upstream_result, provider, actual)
    input_tokens, output_tokens = usage_tokens(chat_response.get("usage"))
    await db.record_usage(config, provider_id, actual, input_tokens, output_tokens, latency, "ok")
    await db.log_request(
        config,
        provider_id,
        model,
        actual,
        want_stream,
        status,
        latency,
        request_body,
        response_text,
        "",
    )
    message = anthropic_response_from_chat(chat_response, actual)
    if want_stream:
        async def generate():
            for line in anthropic_sse_lines(message):
                yield line.encode("utf-8")
        return StreamingResponse(generate(), media_type="text/event-stream", status_code=200, headers=sse_headers())
    return JSONResponse(message)
