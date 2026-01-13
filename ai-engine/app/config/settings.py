from dynaconf import Dynaconf
import os
env = os.getenv("ENVIRONMENT", "development")

settings = Dynaconf(
    environments=True,
    load_dotenv=True,
    sysenv_fallback=True,
    env=env,
    settings_files=["/app/app/config/settings.yml"],
)
