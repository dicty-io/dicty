import transcribe_service
from contextlib import asynccontextmanager

@asynccontextmanager
async def shared_http_client():
    """Yields the process-wide keep-alive AsyncClient (does not close it on exit),
    so repeated LLM/STT calls reuse TLS connections instead of re-handshaking."""
    yield transcribe_service.get_shared_async_client()
