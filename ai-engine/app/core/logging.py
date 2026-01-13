import logging
import pprint
from config import settings

logging.basicConfig(
    level=settings.log_level.upper(), format="%(asctime)s - %(levelname)s - %(message)s"
)

logger = logging.getLogger()

pprint = pprint.pprint
