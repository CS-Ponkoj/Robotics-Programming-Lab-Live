import logging
from waitress import serve
from app import app

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

if __name__ == "__main__":
    logger.info("Starting Waitress production server on http://0.0.0.0:5000")
    serve(app, host="0.0.0.0", port=5000)
