import logging

import uvicorn


logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)


if __name__ == "__main__":
    logging.info("Starting FastAPI on http://0.0.0.0:5000")
    uvicorn.run("app:app", host="0.0.0.0", port=5000, reload=False)
