#!/usr/bin/env python3.10
import logging
from pathlib import Path

from flask import Flask, jsonify, request, send_file
from flask_cors import CORS
import json
import code_tester
from hinter import get_one_sentence_hint

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__, static_url_path="/static")
cors = CORS(app)
BASE_DIR = Path(__file__).resolve().parent
ASSIGNMENTS_DIR = BASE_DIR / "assignments"
STATIC_DIR = BASE_DIR / "static"
MAX_SUBMISSION_CHARS = 50_000


def assignment_path(assignment_id):
    return ASSIGNMENTS_DIR / f"assignment_{assignment_id}.json"


@app.get("/assignments/")
def get_assignments():
    try:
        assignments = [
            json.loads(path.read_text(encoding="utf-8"))
            for path in sorted(ASSIGNMENTS_DIR.glob("assignment_*.json"))
        ]
    except (OSError, json.JSONDecodeError) as exc:
        logger.exception("Failed to load assignments: %s", exc)
        return jsonify(error="Failed to load assignments."), 500
    return jsonify(assignments=assignments)


@app.get("/assignments/<int:assignment_id>")
def get_assignment(assignment_id):
    path = assignment_path(assignment_id)
    if not path.is_file():
        return jsonify(error="Assignment not found.", id=assignment_id), 404

    try:
        assignment = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        logger.exception("Failed to load assignment %s: %s", assignment_id, exc)
        return jsonify(error="Failed to load assignment.", id=assignment_id), 500
    return jsonify(assignment)


@app.post("/grade/<int:assignment_id>")
def grade_assignment(assignment_id):
    if not request.is_json:
        logger.warning(f"Invalid content type: {request.content_type}")
        return jsonify(error="Content-Type must be application/json."), 400

    path = assignment_path(assignment_id)
    if not path.is_file():
        return jsonify(error="Assignment not found.", id=assignment_id), 404

    request_data = request.get_json(silent=True)
    code = request_data.get("code") if isinstance(request_data, dict) else None
    if not isinstance(code, str) or not code.strip():
        logger.warning("No code provided in request.")
        return jsonify(error="A non-empty code string is required."), 400
    if len(code) > MAX_SUBMISSION_CHARS:
        return jsonify(error="Submitted code is too large."), 413

    namespace = {}

    codetester = code_tester.CodeTester(assignment_id, code, namespace=namespace)
    codetester.full_check()

    unittest_results = codetester.get_results_array()
    unittest_pass_results = codetester.get_pass_results()
    logger.info(f"Test results for {id}: {unittest_results}")

    tests_passed = bool(unittest_pass_results) and all(unittest_pass_results)
    
    hint = ""
    if not codetester.exec_success or not tests_passed:
        try:
            assignment_data = json.loads(path.read_text(encoding="utf-8"))
            prompt = assignment_data.get("description", "Solve the problem.")
            
            # Combine code output and execution result for test_output
            test_output = str(codetester.get_exec_result()) + "\n" + str(codetester.get_code_output())
            
            # Generate hint
            hint = get_one_sentence_hint(assignment_id, prompt, code, test_output)
        except Exception as e:
            logger.error(f"Error generating hint: {e}")
            hint = "Could not generate a hint at this time."
    
    response = jsonify({
        "id": assignment_id,
        "tested_vals": codetester.get_tested_vals(),
        "pass": codetester.exec_success and tests_passed,
        "unittest_results": unittest_results,
        "unittest_pass_results": unittest_pass_results,
        "code_exec_result": str(codetester.get_exec_result()),
        "code_output": str(codetester.get_code_output()),
        "ex_success": codetester.exec_success,
        "hint": hint
    })
    
    response.status_code=200
    return response


@app.get("/images/<int:image_id>")
def serve_image(image_id):
    image = STATIC_DIR / f"image{image_id}.png"
    if not image.is_file():
        return jsonify(error="Image not found.", id=image_id), 404
    logger.info(f"Serving image: {image}")
    return send_file(image, mimetype="image/png")

if __name__ == "__main__":
    app.run(host="", port=5000)
