"""Check the configured OpenAI API, then open a temporary terminal chat."""

from pathlib import Path
import sys

from openai import (
    APIConnectionError,
    APIError,
    APIStatusError,
    APITimeoutError,
    AuthenticationError,
    OpenAI,
    PermissionDeniedError,
    RateLimitError,
)

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from config import get_settings  # noqa: E402


def describe_error(error: APIError) -> str:
    if isinstance(error, AuthenticationError):
        return "OpenAI rejected the API key (401). Check the key in .env."
    if isinstance(error, PermissionDeniedError):
        return "The key lacks permission for this request (403). Check project access."
    if isinstance(error, RateLimitError):
        if getattr(error, "code", None) == "insufficient_quota":
            return "The project has no available API quota or credits (429)."
        return "OpenAI returned 429. Check project credits and rate limits."
    if isinstance(error, APITimeoutError):
        return "The request timed out. Check the connection and try again."
    if isinstance(error, APIConnectionError):
        return "Could not reach OpenAI. Check the network and try again."
    if isinstance(error, APIStatusError):
        return (
            f"OpenAI returned HTTP {error.status_code}. "
            "Check model access and project settings."
        )
    return "The OpenAI request failed. Check the project configuration."


def response_text(response: object) -> str | None:
    if response.status != "completed":
        return None
    return response.output_text.strip() or None


def chat(client: OpenAI, model: str) -> int:
    history: list[dict[str, str]] = []
    print("\nChat ready. Type a question, or /exit to quit. Nothing is saved locally.")
    while True:
        try:
            question = input("You> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nChat closed.")
            return 0

        if question.lower() in {"/exit", "exit", "quit"}:
            print("Chat closed.")
            return 0
        if not question:
            continue

        request_history = history[-6:] + [{"role": "user", "content": question}]
        try:
            response = client.responses.create(
                model=model,
                input=request_history,
                max_output_tokens=250,
                store=False,
            )
        except APIError as error:
            print(f"FAIL: {describe_error(error)}")
            continue

        answer = response_text(response)
        if answer is None:
            print("FAIL: OpenAI accepted the request but did not return text.")
            continue
        print(f"AI> {answer}\n")
        history = request_history + [{"role": "assistant", "content": answer}]


def main() -> int:
    settings = get_settings()
    if not settings.openai_api_key:
        print("FAIL: OPENAI_API_KEY is missing from the app configuration.")
        return 1

    client = OpenAI(
        api_key=settings.openai_api_key,
        timeout=20.0,
        max_retries=0,
    )
    try:
        response = client.responses.create(
            model=settings.openai_hint_model,
            input="Reply with OK.",
            max_output_tokens=16,
            store=False,
        )
    except APIError as error:
        print(f"FAIL: {describe_error(error)}")
        return 1

    if response_text(response) is None:
        print("FAIL: OpenAI accepted the request but did not return text.")
        return 1

    print(
        f"PASS: OpenAI responded using the configured model "
        f"({settings.openai_hint_model})."
    )
    return chat(client, settings.openai_hint_model)


if __name__ == "__main__":
    raise SystemExit(main())
