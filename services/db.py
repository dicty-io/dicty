import os
import logging
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

logger = logging.getLogger("dicty.db")

DATABASE_URL = os.getenv("DATABASE_URL")

Base = declarative_base()
engine = None
SessionLocal = None
DB_AVAILABLE = False

if DATABASE_URL:
    try:
        if DATABASE_URL.startswith("postgres://"):
            DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)
        engine = create_engine(DATABASE_URL, pool_pre_ping=True)
        SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
        DB_AVAILABLE = True
        logger.info("Database configured successfully.")
    except Exception as e:
        logger.warning(f"Failed to configure database: {e}. Running in Offline Mode.")
        DB_AVAILABLE = False
else:
    logger.warning("DATABASE_URL not set. Running in Offline Mode.")

def get_db():
    if not DB_AVAILABLE or SessionLocal is None:
        yield None
        return
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def init_db():
    global DB_AVAILABLE
    if not DB_AVAILABLE or engine is None:
        logger.warning("Skipping DB initialization (Offline Mode).")
        return
    try:
        import models  # noqa: F401
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables initialized successfully.")
    except Exception as e:
        logger.error(f"Failed to initialize DB tables: {e}. Switching to Offline Mode.")
        DB_AVAILABLE = False
