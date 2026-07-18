"""Protocol conversion between OpenAI Chat, Responses, Anthropic and Ollama."""

from __future__ import annotations

import json
import time
import uuid
from typing import Any

from .config import normalize_protocol


def safe_json_loads(value: Any, default: Any = None) -> Any:
    if default is None:
        default = {}
    if not isinstance(value, str):
        return value if value is not None else default
    try:
        return json.loads(value)
    except Exception:
        return default


def uid(prefix: str = "") -> str:
    return f"{prefix}{uuid.uuid4().hex[:16]}"


def response_content_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    text = ""
    for part in content:
        if isinstance(part, str):
            text += part
            continue
        if not isinstance(part, dict):
            continue
        if isinstance(part.get("text"), str):
            text += part["text"]
        elif "content" in part:
            text += response_content_text(part.get("content"))
        elif "output_text" in part:
            text += response_content_text(part.get("output_text"))
    return text


def response_value_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    if value is None:
        return ""
    if isinstance(value, (list, dict)):
        text = response_content_text(value)
        return text if text != "" else json.dumps(value, ensure_ascii=False)
    return str(value)


def merge_streamed_tool_name(current: str, delta: str) -> str:
    current = str(current or "")
    delta = str(delta or "")
    if not delta:
        return current
    if not current:
        return delta
    if delta == current or current.endswith(delta):
        return current
    if delta.startswith(current):
        return delta
    return current + delta


def normalize_chat_role(role: str) -> str:
    if role == "developer":
        return "system"
    if role in {"system", "user", "assistant", "tool"}:
        return role
    return "user"


def normalize_json_schema(value: Any, key: str = "") -> Any:
    if not isinstance(value, dict):
        return value
    array_keys = {"required", "enum", "anyOf", "allOf", "oneOf", "prefixItems"}
    if not value:
        return [] if key in array_keys else {}
    return {child_key: normalize_json_schema(child_value, str(child_key)) for child_key, child_value in value.items()}


def usage_tokens(usage: Any) -> tuple[int, int]:
    if not isinstance(usage, dict):
        return 0, 0
    input_tokens = usage.get("prompt_tokens", usage.get("input_tokens", 0)) or 0
    output_tokens = usage.get("completion_tokens", usage.get("output_tokens", 0)) or 0
    try:
        return int(input_tokens), int(output_tokens)
    except (TypeError, ValueError):
        return 0, 0


def safe_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def chat_to_anthropic_payload(body: dict[str, Any]) -> dict[str, Any]:
    system = ""
    messages: list[dict[str, Any]] = []
    for message in body.get("messages") or []:
        if not isinstance(message, dict):
            continue
        role = message.get("role") or "user"
        if role in {"system", "developer"}:
            system += response_content_text(message.get("content")) + "\n"
            continue
        if role == "tool":
            messages.append(
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": message.get("tool_call_id") or "",
                            "content": response_content_text(message.get("content")),
                        }
                    ],
                }
            )
            continue
        content: list[dict[str, Any]] = []
        text = response_content_text(message.get("content"))
        if text != "":
            content.append({"type": "text", "text": text})
        for tool_call in message.get("tool_calls") or []:
            if not isinstance(tool_call, dict):
                continue
            function = tool_call.get("function") if isinstance(tool_call.get("function"), dict) else {}
            arguments = function.get("arguments", "{}")
            decoded = safe_json_loads(arguments, {})
            if not isinstance(decoded, dict):
                decoded = {}
            content.append(
                {
                    "type": "tool_use",
                    "id": tool_call.get("id") or uid("toolu_"),
                    "name": function.get("name") or "",
                    "input": decoded,
                }
            )
        if not content:
            content.append({"type": "text", "text": ""})
        messages.append({"role": "assistant" if role == "assistant" else "user", "content": content})

    payload: dict[str, Any] = {
        "max_tokens": max(1, safe_int(body.get("max_tokens") or 1024, 1024)),
        "messages": messages,
        "stream": bool(body.get("stream")),
    }
    if system.strip():
        payload["system"] = system.strip()
    for field in ("temperature", "top_p", "stop_sequences"):
        if field in body:
            payload[field] = body[field]
    if "stop" in body and "stop_sequences" not in payload:
        stop = body["stop"]
        payload["stop_sequences"] = stop if isinstance(stop, list) else [stop]
    if "tools" in body:
        tools = []
        for tool in body.get("tools") or []:
            function = tool.get("function") if isinstance(tool, dict) and isinstance(tool.get("function"), dict) else {}
            tools.append(
                {
                    "name": function.get("name") or "",
                    "description": function.get("description") or "",
                    "input_schema": normalize_json_schema(function.get("parameters") or {}),
                }
            )
        payload["tools"] = tools
    if "tool_choice" in body:
        choice = body["tool_choice"]
        if choice == "auto":
            payload["tool_choice"] = {"type": "auto"}
        elif choice == "required":
            payload["tool_choice"] = {"type": "any"}
        elif isinstance(choice, dict) and isinstance(choice.get("function"), dict):
            payload["tool_choice"] = {"type": "tool", "name": choice["function"].get("name") or ""}
    return payload


def anthropic_to_chat_response(result: dict[str, Any], model: str) -> dict[str, Any]:
    content = ""
    tool_calls = []
    for part in result.get("content") or []:
        if not isinstance(part, dict):
            continue
        if part.get("type") == "tool_use":
            tool_calls.append(
                {
                    "id": part.get("id") or uid("call_"),
                    "type": "function",
                    "function": {
                        "name": part.get("name") or "",
                        "arguments": json.dumps(part.get("input") or {}, ensure_ascii=False),
                    },
                }
            )
        elif "text" in part:
            content += str(part.get("text") or "")
    input_tokens, output_tokens = usage_tokens(result.get("usage"))
    message: dict[str, Any] = {"role": "assistant", "content": content}
    if tool_calls:
        message["tool_calls"] = tool_calls
    return {
        "id": result.get("id") or uid("chatcmpl-"),
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [
            {
                "index": 0,
                "message": message,
                "finish_reason": "tool_calls" if tool_calls else "stop",
            }
        ],
        "usage": {
            "prompt_tokens": input_tokens,
            "completion_tokens": output_tokens,
            "total_tokens": input_tokens + output_tokens,
        },
    }


def ollama_to_chat_response(result: dict[str, Any], model: str) -> dict[str, Any]:
    message = result.get("message") if isinstance(result.get("message"), dict) else {"role": "assistant", "content": ""}
    input_tokens = safe_int(result.get("prompt_eval_count") or 0, 0)
    output_tokens = safe_int(result.get("eval_count") or 0, 0)
    return {
        "id": uid("chatcmpl-"),
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [{"index": 0, "message": message, "finish_reason": "stop"}],
        "usage": {
            "prompt_tokens": input_tokens,
            "completion_tokens": output_tokens,
            "total_tokens": input_tokens + output_tokens,
        },
    }


def chat_tools_to_responses(tools: Any) -> list[dict[str, Any]]:
    if not isinstance(tools, list):
        return tools
    result = []
    for tool in tools:
        if not isinstance(tool, dict) or tool.get("type") != "function":
            continue
        function = tool.get("function") if isinstance(tool.get("function"), dict) else None
        if not function:
            continue
        item = {
            "type": "function",
            "name": function.get("name") or "",
            "description": function.get("description") or "",
            "parameters": normalize_json_schema(function.get("parameters") or {}),
        }
        if "strict" in function:
            item["strict"] = bool(function.get("strict"))
        result.append(item)
    return result


def responses_tools_to_chat(tools: Any) -> list[dict[str, Any]]:
    if not isinstance(tools, list):
        return tools
    result = []
    for tool in tools:
        if not isinstance(tool, dict):
            continue
        if tool.get("type") == "function":
            if isinstance(tool.get("function"), dict):
                item = dict(tool)
                if "parameters" in item["function"]:
                    item["function"]["parameters"] = normalize_json_schema(item["function"]["parameters"])
                result.append(item)
                continue
            function = {
                "name": tool.get("name") or "",
                "description": tool.get("description") or "",
                "parameters": normalize_json_schema(tool.get("parameters") or {}),
            }
            if "strict" in tool:
                function["strict"] = bool(tool.get("strict"))
            result.append({"type": "function", "function": function})
    return result


def chat_to_responses_payload(body: dict[str, Any]) -> dict[str, Any]:
    payload = dict(body)
    for field in ("messages", "max_tokens", "n", "logprobs", "top_logprobs"):
        payload.pop(field, None)
    input_items: list[dict[str, Any]] = []
    for message in body.get("messages") or []:
        if not isinstance(message, dict):
            continue
        role = message.get("role") or "user"
        if role == "tool":
            input_items.append(
                {
                    "type": "function_call_output",
                    "call_id": message.get("tool_call_id") or "",
                    "output": response_content_text(message.get("content")),
                }
            )
            continue
        content = response_content_text(message.get("content"))
        if content != "":
            input_items.append(
                {
                    "role": "developer" if role in {"system", "developer"} else role,
                    "content": content,
                }
            )
        for tool_call in message.get("tool_calls") or []:
            if not isinstance(tool_call, dict):
                continue
            function = tool_call.get("function") if isinstance(tool_call.get("function"), dict) else {}
            input_items.append(
                {
                    "type": "function_call",
                    "call_id": tool_call.get("id") or uid("call_"),
                    "name": function.get("name") or "",
                    "arguments": response_value_text(function.get("arguments") or ""),
                }
            )
    payload["input"] = input_items
    if "max_tokens" in body and "max_output_tokens" not in payload:
        payload["max_output_tokens"] = safe_int(body["max_tokens"], 1024)
    if "tools" in payload:
        payload["tools"] = chat_tools_to_responses(payload.get("tools"))
        if not payload["tools"]:
            payload.pop("tools", None)
    if "tool_choice" in payload:
        choice = payload["tool_choice"]
        if isinstance(choice, dict) and isinstance(choice.get("function"), dict):
            payload["tool_choice"] = {"type": "function", "name": choice["function"].get("name") or ""}
    return payload


def responses_text_from_result(result: dict[str, Any]) -> str:
    if isinstance(result.get("output_text"), str):
        return result["output_text"]
    text = ""
    for item in result.get("output") or []:
        if isinstance(item, dict) and item.get("type") == "message":
            text += response_content_text(item.get("content"))
    return text


def chat_response_from_responses(result: dict[str, Any], model: str) -> dict[str, Any]:
    tool_calls = []
    for item in result.get("output") or []:
        if isinstance(item, dict) and item.get("type") == "function_call":
            tool_calls.append(
                {
                    "id": item.get("call_id") or item.get("id") or uid("call_"),
                    "type": "function",
                    "function": {
                        "name": item.get("name") or "",
                        "arguments": item.get("arguments") or "",
                    },
                }
            )
    message: dict[str, Any] = {"role": "assistant", "content": responses_text_from_result(result)}
    if tool_calls:
        message["tool_calls"] = tool_calls
    input_tokens, output_tokens = usage_tokens(result.get("usage"))
    return {
        "id": result.get("id") or uid("chatcmpl-"),
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [
            {
                "index": 0,
                "message": message,
                "finish_reason": "tool_calls" if tool_calls else "stop",
            }
        ],
        "usage": {
            "prompt_tokens": input_tokens,
            "completion_tokens": output_tokens,
            "total_tokens": input_tokens + output_tokens,
        },
    }


def normalize_upstream_chat_response(result: dict[str, Any], provider: dict[str, Any], model: str) -> dict[str, Any]:
    ptype = normalize_protocol("", provider)
    if ptype == "responses":
        return chat_response_from_responses(result, model)
    if ptype == "anthropic":
        return anthropic_to_chat_response(result, model)
    if ptype == "ollama":
        return ollama_to_chat_response(result, model)
    return result


def responses_messages(body: dict[str, Any]) -> list[dict[str, Any]]:
    messages: list[dict[str, Any]] = []
    if str(body.get("instructions") or "").strip():
        messages.append({"role": "system", "content": str(body.get("instructions"))})
    if "input" not in body and isinstance(body.get("messages"), list):
        for message in body["messages"]:
            if isinstance(message, dict) and "role" in message:
                messages.append(
                    {
                        "role": normalize_chat_role(message.get("role") or "user"),
                        "content": response_content_text(message.get("content")),
                    }
                )
        return messages
    input_value = body.get("input", "")
    if isinstance(input_value, str):
        if input_value != "":
            messages.append({"role": "user", "content": input_value})
        return messages
    if not isinstance(input_value, list):
        return messages
    for item in input_value:
        if isinstance(item, str):
            messages.append({"role": "user", "content": item})
            continue
        if not isinstance(item, dict):
            continue
        item_type = item.get("type") or ""
        if item_type == "function_call":
            call_id = item.get("call_id") or item.get("id") or uid("call_")
            messages.append(
                {
                    "role": "assistant",
                    "content": "",
                    "tool_calls": [
                        {
                            "id": call_id,
                            "type": "function",
                            "function": {
                                "name": item.get("name") or "",
                                "arguments": response_value_text(item.get("arguments") or ""),
                            },
                        }
                    ],
                }
            )
            continue
        if item_type == "function_call_output":
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": item.get("call_id") or "",
                    "content": response_value_text(item.get("output") or ""),
                }
            )
            continue
        if item_type == "message" or "role" in item:
            role = normalize_chat_role(item.get("role") or "user")
            message = {"role": role, "content": response_content_text(item.get("content"))}
            if role == "tool" and "tool_call_id" in item:
                message["tool_call_id"] = item["tool_call_id"]
            messages.append(message)
            continue
        text = response_content_text(item)
        if text:
            messages.append({"role": "user", "content": text})
    return messages


def responses_tool_choice_to_chat(choice: Any) -> Any:
    if isinstance(choice, dict) and choice.get("type") == "function" and "name" in choice:
        return {"type": "function", "function": {"name": choice.get("name") or ""}}
    return choice


def responses_chat_payload(body: dict[str, Any], messages: list[dict[str, Any]]) -> dict[str, Any]:
    payload = dict(body)
    for field in (
        "input",
        "instructions",
        "previous_response_id",
        "max_output_tokens",
        "metadata",
        "store",
        "truncation",
        "reasoning",
        "text",
        "include",
        "background",
        "conversation",
        "prompt",
        "prompt_cache_key",
        "safety_identifier",
    ):
        payload.pop(field, None)
    payload["messages"] = messages
    if "max_output_tokens" in body and "max_tokens" not in payload:
        payload["max_tokens"] = safe_int(body["max_output_tokens"], 1024)
    if "tools" in payload:
        payload["tools"] = responses_tools_to_chat(payload.get("tools"))
        if not payload["tools"]:
            payload.pop("tools", None)
    if "tool_choice" in payload:
        payload["tool_choice"] = responses_tool_choice_to_chat(payload.get("tool_choice"))
    return payload


def anthropic_messages_to_chat(body: dict[str, Any]) -> list[dict[str, Any]]:
    messages: list[dict[str, Any]] = []
    if str(body.get("system") or "").strip():
        messages.append({"role": "system", "content": str(body.get("system"))})
    for message in body.get("messages") or []:
        if not isinstance(message, dict):
            continue
        role = message.get("role") or "user"
        content = message.get("content")
        if isinstance(content, str):
            messages.append({"role": normalize_chat_role(role), "content": content})
            continue
        text = ""
        tool_calls = []
        tool_results = []
        for part in content or []:
            if not isinstance(part, dict):
                continue
            ptype = part.get("type") or ""
            if ptype in {"text", "input_text"}:
                text += part.get("text") or ""
            elif ptype == "tool_use":
                input_value = part.get("input") or {}
                tool_calls.append(
                    {
                        "id": part.get("id") or uid("call_"),
                        "type": "function",
                        "function": {
                            "name": part.get("name") or "",
                            "arguments": input_value if isinstance(input_value, str) else json.dumps(input_value, ensure_ascii=False),
                        },
                    }
                )
            elif ptype == "tool_result":
                tool_results.append(
                    {
                        "role": "tool",
                        "tool_call_id": part.get("tool_use_id") or "",
                        "content": response_content_text(part.get("content")),
                    }
                )
        if tool_calls:
            messages.append({"role": "assistant", "content": text, "tool_calls": tool_calls})
        elif text != "":
            messages.append({"role": normalize_chat_role(role), "content": text})
        messages.extend(tool_results)
    return messages


def anthropic_tools_to_chat(tools: Any) -> list[dict[str, Any]]:
    if not isinstance(tools, list):
        return tools
    result = []
    for tool in tools:
        if not isinstance(tool, dict):
            continue
        schema = tool.get("input_schema", tool.get("parameters", {}))
        result.append(
            {
                "type": "function",
                "function": {
                    "name": tool.get("name") or "",
                    "description": tool.get("description") or "",
                    "parameters": normalize_json_schema(schema or {}),
                },
            }
        )
    return result


def anthropic_tool_choice_to_chat(choice: Any) -> Any:
    if not isinstance(choice, dict) or "type" not in choice:
        return choice
    if choice["type"] == "tool":
        return {"type": "function", "function": {"name": choice.get("name") or ""}}
    if choice["type"] == "any":
        return "required"
    if choice["type"] == "auto":
        return "auto"
    return choice


def anthropic_chat_payload(body: dict[str, Any]) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "model": body.get("model") or "",
        "messages": anthropic_messages_to_chat(body),
        "max_tokens": max(1, safe_int(body.get("max_tokens") or 1024, 1024)),
        "stream": False,
    }
    for field in ("temperature", "top_p", "stop"):
        if field in body:
            payload[field] = body[field]
    if "tools" in body:
        payload["tools"] = anthropic_tools_to_chat(body.get("tools"))
    if "tool_choice" in body:
        payload["tool_choice"] = anthropic_tool_choice_to_chat(body.get("tool_choice"))
    return payload


def anthropic_content_from_chat(chat_response: dict[str, Any]) -> list[dict[str, Any]]:
    if chat_response.get("type") == "message" and "content" in chat_response:
        return chat_response["content"]
    message = ((chat_response.get("choices") or [{}])[0].get("message") or {})
    content: list[dict[str, Any]] = []
    text = response_content_text(message.get("content"))
    if text != "":
        content.append({"type": "text", "text": text})
    for tool_call in message.get("tool_calls") or []:
        if not isinstance(tool_call, dict):
            continue
        function = tool_call.get("function") if isinstance(tool_call.get("function"), dict) else {}
        arguments = function.get("arguments") or "{}"
        decoded = safe_json_loads(arguments, {})
        if not isinstance(decoded, dict):
            decoded = {}
        content.append(
            {
                "type": "tool_use",
                "id": tool_call.get("id") or uid("toolu_"),
                "name": function.get("name") or "",
                "input": decoded if isinstance(decoded, dict) else {},
            }
        )
    if not content:
        content.append({"type": "text", "text": ""})
    return content


def anthropic_stop_reason(chat_response: dict[str, Any]) -> str:
    if "stop_reason" in chat_response:
        return chat_response["stop_reason"]
    message = ((chat_response.get("choices") or [{}])[0].get("message") or {})
    if message.get("tool_calls"):
        return "tool_use"
    finish = ((chat_response.get("choices") or [{}])[0].get("finish_reason") or "stop")
    if finish == "length":
        return "max_tokens"
    return "end_turn"


def anthropic_response_from_chat(chat_response: dict[str, Any], model: str) -> dict[str, Any]:
    if chat_response.get("type") == "message" and "content" in chat_response:
        return chat_response
    input_tokens, output_tokens = usage_tokens(chat_response.get("usage"))
    return {
        "id": uid("msg_"),
        "type": "message",
        "role": "assistant",
        "model": model,
        "content": anthropic_content_from_chat(chat_response),
        "stop_reason": anthropic_stop_reason(chat_response),
        "stop_sequence": None,
        "usage": {"input_tokens": input_tokens, "output_tokens": output_tokens},
    }


def chat_response_has_output(chat: dict[str, Any], text: str | None = None) -> bool:
    message = ((chat.get("choices") or [{}])[0].get("message") or {})
    if not isinstance(message, dict):
        message = {}
    if text is None:
        text = response_content_text(message.get("content"))
    if str(text) != "":
        return True
    tool_calls = message.get("tool_calls")
    return isinstance(tool_calls, list) and bool(tool_calls)


def responses_output_text(chat: dict[str, Any]) -> str:
    message = ((chat.get("choices") or [{}])[0].get("message") or {})
    return response_content_text(message.get("content"))


def responses_output_items_from_chat(chat: dict[str, Any], message_id: str, text: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    message = ((chat.get("choices") or [{}])[0].get("message") or {})
    if text != "":
        items.append(
            {
                "id": message_id,
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [{"type": "output_text", "text": text, "annotations": []}],
            }
        )
    for tool_call in message.get("tool_calls") or []:
        if not isinstance(tool_call, dict):
            continue
        function = tool_call.get("function") if isinstance(tool_call.get("function"), dict) else {}
        items.append(
            {
                "id": uid("fc_"),
                "type": "function_call",
                "status": "completed",
                "call_id": tool_call.get("id") or uid("call_"),
                "name": function.get("name") or "",
                "arguments": function.get("arguments") or "",
            }
        )
    return items


def chat_messages_from_response_output(output: list[dict[str, Any]]) -> list[dict[str, Any]]:
    text = ""
    tool_calls = []
    for item in output:
        if not isinstance(item, dict) or "type" not in item:
            continue
        if item["type"] == "message":
            text += response_content_text(item.get("content"))
            continue
        if item["type"] == "function_call":
            tool_calls.append(
                {
                    "id": item.get("call_id") or item.get("id") or uid("call_"),
                    "type": "function",
                    "function": {
                        "name": item.get("name") or "",
                        "arguments": item.get("arguments") or "",
                    },
                }
            )
    if tool_calls:
        return [{"role": "assistant", "content": text, "tool_calls": tool_calls}]
    return [{"role": "assistant", "content": text}]


def responses_usage(input_tokens: int, output_tokens: int) -> dict[str, int]:
    return {
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "total_tokens": input_tokens + output_tokens,
    }


def responses_object(
    response_id: str,
    model: str,
    status: str,
    output: list[dict[str, Any]],
    input_tokens: int,
    output_tokens: int,
    error: str | None = None,
) -> dict[str, Any]:
    response = {
        "id": response_id,
        "object": "response",
        "created_at": int(time.time()),
        "status": status,
        "model": model,
        "output": output,
        "usage": responses_usage(input_tokens, output_tokens),
    }
    if error is not None:
        response["error"] = {"message": error}
    return response


def upstream_request(provider: dict[str, Any], model: str, body: dict[str, Any], protocol: str = "") -> tuple[str, dict[str, str], dict[str, Any]]:
    ptype = normalize_protocol(protocol, provider)
    base = str(provider.get("base_url") or "").rstrip("/")
    key = str(provider.get("api_key") or "")
    if ptype == "ollama":
        url = base + "/api/chat"
        payload = dict(body)
        payload["model"] = model
        if "max_tokens" in payload:
            options = payload.get("options") if isinstance(payload.get("options"), dict) else {}
            options["num_predict"] = safe_int(payload.pop("max_tokens"), 1024)
            payload["options"] = options
        return url, {"Content-Type": "application/json"}, payload
    if ptype == "responses":
        url = base + "/responses"
        payload = chat_to_responses_payload(body)
        payload["model"] = model
        return url, {"Content-Type": "application/json", "Authorization": f"Bearer {key}"}, payload
    if ptype == "anthropic":
        url = (base if base.endswith("/v1") else base + "/v1") + "/messages"
        payload = chat_to_anthropic_payload(body)
        payload["model"] = model
        return (
            url,
            {
                "Content-Type": "application/json",
                "x-api-key": key,
                "anthropic-version": "2023-06-01",
            },
            payload,
        )
    url = base + "/chat/completions"
    payload = dict(body)
    payload["model"] = model
    return url, {"Content-Type": "application/json", "Authorization": f"Bearer {key}"}, payload


def chat_stream_chunks(result: dict[str, Any], model: str) -> list[str]:
    rid = result.get("id") or uid("chatcmpl-")
    created = safe_int(result.get("created") or time.time(), int(time.time()))
    choice = ((result.get("choices") or [{}])[0] or {})
    message = choice.get("message") if isinstance(choice.get("message"), dict) else {}
    base = {"id": rid, "object": "chat.completion.chunk", "created": created, "model": model}
    chunks = []
    start = dict(base)
    start["choices"] = [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}]
    chunks.append("data: " + json.dumps(start, ensure_ascii=False) + "\n\n")
    delta: dict[str, Any] = {}
    content = response_content_text(message.get("content"))
    if content:
        delta["content"] = content
    if message.get("tool_calls"):
        delta["tool_calls"] = message["tool_calls"]
    if delta:
        chunk = dict(base)
        chunk["choices"] = [{"index": 0, "delta": delta, "finish_reason": None}]
        chunks.append("data: " + json.dumps(chunk, ensure_ascii=False) + "\n\n")
    done = dict(base)
    done["choices"] = [{"index": 0, "delta": {}, "finish_reason": choice.get("finish_reason") or "stop"}]
    if "usage" in result:
        done["usage"] = result["usage"]
    chunks.append("data: " + json.dumps(done, ensure_ascii=False) + "\n\n")
    chunks.append("data: [DONE]\n\n")
    return chunks


def anthropic_sse_lines(message: dict[str, Any]) -> list[str]:
    lines: list[str] = []

    def emit(event: str, data: dict[str, Any]) -> None:
        if "type" not in data:
            data = dict(data)
            data["type"] = event
        lines.append(f"event: {event}\n")
        lines.append("data: " + json.dumps(data, ensure_ascii=False) + "\n\n")

    start = dict(message)
    start["content"] = []
    start["stop_reason"] = None
    emit("message_start", {"message": start, "type": "message_start"})
    for index, block in enumerate(message.get("content") or []):
        if not isinstance(block, dict):
            continue
        if block.get("type") == "text":
            emit("content_block_start", {"index": index, "content_block": {"type": "text", "text": ""}, "type": "content_block_start"})
            if block.get("text"):
                emit(
                    "content_block_delta",
                    {
                        "index": index,
                        "delta": {"type": "text_delta", "text": block.get("text") or ""},
                        "type": "content_block_delta",
                    },
                )
            emit("content_block_stop", {"index": index, "type": "content_block_stop"})
        elif block.get("type") == "tool_use":
            start_block = dict(block)
            start_block["input"] = {}
            emit("content_block_start", {"index": index, "content_block": start_block, "type": "content_block_start"})
            emit(
                "content_block_delta",
                {
                    "index": index,
                    "delta": {
                        "type": "input_json_delta",
                        "partial_json": json.dumps(block.get("input") or {}, ensure_ascii=False),
                    },
                    "type": "content_block_delta",
                },
            )
            emit("content_block_stop", {"index": index, "type": "content_block_stop"})
    emit(
        "message_delta",
        {
            "delta": {
                "stop_reason": message.get("stop_reason") or "end_turn",
                "stop_sequence": None,
            },
            "usage": {"output_tokens": ((message.get("usage") or {}).get("output_tokens") or 0)},
            "type": "message_delta",
        },
    )
    emit("message_stop", {"type": "message_stop"})
    return lines


def responses_sse(event_type: str, data: dict[str, Any]) -> str:
    payload = dict(data)
    payload.setdefault("type", event_type)
    return f"event: {event_type}\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"



def unwrap_upstream_error(raw: Any, fallback: str = "") -> str:
    if raw is None:
        return fallback or ""
    if isinstance(raw, dict):
        err = raw.get("error")
        if isinstance(err, dict):
            msg = err.get("message") or err.get("detail") or err.get("code")
            if msg:
                return str(msg)
        if raw.get("message"):
            return str(raw.get("message"))
        try:
            return json.dumps(raw, ensure_ascii=False)
        except Exception:
            return str(raw)
    text = str(raw)
    if not text:
        return fallback or ""
    try:
        data = json.loads(text)
    except Exception:
        return text
    return unwrap_upstream_error(data, text)



def responses_upstream_request(provider: dict[str, Any], model: str, body: dict[str, Any]) -> tuple[str, dict[str, str], dict[str, Any]]:
    """Pass-through Responses payload to a responses-compatible provider."""
    base = str(provider.get("base_url") or "").rstrip("/")
    key = str(provider.get("api_key") or "")
    url = base + "/responses"
    payload = dict(body)
    payload["model"] = model
    return url, {"Content-Type": "application/json", "Authorization": f"Bearer {key}"}, payload


def anthropic_native_upstream_request(provider: dict[str, Any], model: str, body: dict[str, Any]) -> tuple[str, dict[str, str], dict[str, Any]]:
    base = str(provider.get("base_url") or "").rstrip("/")
    key = str(provider.get("api_key") or "")
    url = (base if base.endswith("/v1") else base + "/v1") + "/messages"
    payload = dict(body)
    payload["model"] = model
    return (
        url,
        {
            "Content-Type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        },
        payload,
    )
