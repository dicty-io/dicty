import uuid
from datetime import datetime
from sqlalchemy import Column, String, Boolean, DateTime, Integer
from db import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, autoincrement=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=True)  # Nullable for Google login or external auth
    is_pro = Column(Boolean, default=False, nullable=False)
    subscription_tier = Column(String, default='free')
    compute_balance = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
