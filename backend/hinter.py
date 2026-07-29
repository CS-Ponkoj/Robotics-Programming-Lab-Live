# hinter.py

import os
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()


def get_one_sentence_hint(assignment_id, prompt, code, test_output, client=None):
    """
    Call ChatGPT to generate exactly one concise sentence hint.
    
    Parameters:
      - assignment_id: str, an identifier for the exercise
      - prompt:        str, the text of the assignment/problem
      - code:          str, the student's submitted code
      - test_output:   str, the output or error from running unit tests

    Returns:
      - hint: str, a single sentence guiding the student towards fixing their mistake
    """

    # 2. Define the system message that sets the model's role
    system_msg = (
        "You are an expert coding tutor. "
        "Provide exactly one concise sentence hint (no code) to help the student fix their mistake."
    )

    # 3. Build the user message with all context
    user_msg = (
        f"Assignment: {assignment_id}\n"             # reference for tracking
        f"Problem: {prompt}\n\n"                     # the actual assignment prompt
        f"Student's code:\n```python\n{code}\n```\n\n" # the code they wrote
        f"Test output:\n{test_output}\n"              # what went wrong when tests ran
    )

    try:
        if client is None:
            client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

        resp = client.chat.completions.create(
            model=os.getenv("OPENAI_HINT_MODEL", "gpt-4.1-mini"),
            messages=[
                {"role": "system", "content": system_msg},
                {"role": "user",   "content": user_msg},
            ],
            temperature=0.0,         # deterministic output
            max_tokens=30            # enough for one sentence
        )

        # 5. Extract and return just the text of the hint
        return resp.choices[0].message.content.strip()
    except Exception as e:
        print(f"Error calling OpenAI API: {e}")
        return "Hint unavailable. Please check your logic and try again."
