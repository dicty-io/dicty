import os
import json
import httpx
from contextlib import asynccontextmanager

_fallback_async_client: httpx.AsyncClient | None = None

@asynccontextmanager
async def _shared_client():
    global _fallback_async_client
    try:
        from transcribe_service import get_shared_async_client
        yield get_shared_async_client()
    except ImportError:
        if _fallback_async_client is None or _fallback_async_client.is_closed:
            _fallback_async_client = httpx.AsyncClient(timeout=60.0)
        yield _fallback_async_client

class LLMService:
    def __init__(self):
        self.openrouter_key = os.getenv("OPENROUTER_API_KEY")
        self.ollama_base_url = os.getenv("OLLAMA_BASE_URL")
        self.default_model = os.getenv("LLM_MODEL", "openai/gpt-4o-mini")

    async def generate(self, prompt: str, system_prompt: str = "You are an AI assistant.", model: str = None, api_key: str = None, provider: str = None, base_url: str = None, temperature: float = 0.1) -> str:
        selected_model = model or self.default_model or os.getenv("LLM_MODEL", "openai/gpt-4o-mini")
        
        if provider == "dicty_cloud":
            cloud_key = api_key or os.getenv("DICTY_JWT_TOKEN")
            if not cloud_key:
                try:
                    from auth import SecureAuthManager
                    cloud_key = SecureAuthManager.get_jwt_token()
                except Exception:
                    pass
            if not cloud_key or cloud_key.startswith("your-"):
                raise ValueError("Dicty Cloud session token is missing. Please sign in to your Dicty account.")
            return await self._call_dicty_cloud(prompt, system_prompt, model=selected_model, api_key=cloud_key, temperature=temperature)
            
        key = api_key or self.openrouter_key or os.getenv("OPENROUTER_API_KEY") or os.getenv("LLM_API_KEY")
        if provider == "openrouter":
            if not key or key.startswith("your-"):
                raise ValueError("OpenRouter API key is missing. Please configure your key in Settings or switch to Dicty Cloud.")
            return await self._call_openrouter(prompt, system_prompt, model=selected_model, api_key=key, temperature=temperature)
        elif provider in ["local", "lmstudio"] or ((not provider or not key) and (self.ollama_base_url or base_url)):
            return await self._call_ollama(prompt, system_prompt, model=selected_model, base_url=base_url)
        elif key and not key.startswith("your-"):
            return await self._call_openrouter(prompt, system_prompt, model=selected_model, api_key=key, temperature=temperature)
        else:
            raise ValueError("Neither OpenRouter API key nor Ollama Base URL is configured properly.")

    async def _call_dicty_cloud(self, prompt: str, system_prompt: str, model: str = None, api_key: str = None, temperature: float = 0.1) -> str:
        dicty_cloud_url = os.getenv("DICTY_CLOUD_URL", "https://dicty-backend.dicty-backend.workers.dev")
        url = f"{dicty_cloud_url}/v1/chat/completions"
        headers = {
            "Authorization": f"Bearer {api_key}",
            "HTTP-Referer": "https://github.com/vkazmin/dicty",
            "Content-Type": "application/json"
        }
        
        target_model = model or self.default_model or "openai/gpt-4o-mini"
        payload = {
            "model": target_model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt}
            ],
            "temperature": temperature
        }
        
        async with _shared_client() as client:
            response = await client.post(url, json=payload, headers=headers, timeout=120.0)
            if response.status_code == 402:
                raise ValueError("Payment Required: Dicty Cloud credits exhausted.")
            if response.status_code != 200:
                print(f"[!] Dicty Cloud API Error ({response.status_code}): {response.text}")
                err_msg = f"Dicty Cloud Error ({response.status_code}): {response.text}"
                try:
                    err_json = response.json()
                    err_val = err_json.get("error", "")
                    if isinstance(err_val, dict):
                        err_msg = err_val.get("message", str(err_val))
                    elif err_val:
                        err_msg = str(err_val)
                except Exception:
                    pass
                raise ValueError(err_msg)
            res_json = response.json()
            return res_json["choices"][0]["message"]["content"]

    async def _call_openrouter(self, prompt: str, system_prompt: str, model: str = None, api_key: str = None, temperature: float = 0.1) -> str:
        url = "https://openrouter.ai/api/v1/chat/completions"
        key = api_key or self.openrouter_key or os.getenv("OPENROUTER_API_KEY") or os.getenv("LLM_API_KEY")
        headers = {
            "Authorization": f"Bearer {key}",
            "HTTP-Referer": "https://github.com/vkazmin/dicty",
            "Content-Type": "application/json"
        }
        
        target_model = model or self.default_model

        payload = {
            "model": target_model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt}
            ],
            "temperature": temperature
        }
        
        # Layer 1: Provider-aware non-thinking parameters on OpenRouter
        # OpenRouter's universal exclusion strips any internal thinking tokens from the output
        reasoning_cfg = {"exclude": True}
        
        model_lower = target_model.lower()
        if "openai" in model_lower or "/o1" in model_lower or "/o3" in model_lower:
            # OpenAI o-series supports reasoning effort 'low'
            reasoning_cfg["effort"] = "low"
        elif "anthropic" in model_lower or "claude" in model_lower:
            # Claude 3.7 Sonnet supports effort 'none' or 'low' to disable extended thinking
            reasoning_cfg["effort"] = "none"
        elif "gemini" in model_lower or "google" in model_lower:
            # Google Gemini 2.0 Flash Thinking / Flash supports effort 'none'
            reasoning_cfg["effort"] = "none"
        elif "minimax" in model_lower or "moonshot" in model_lower or "kimi" in model_lower:
            # Minimax / Kimi models support effort 'none'
            reasoning_cfg["effort"] = "none"
        elif "qwen" in model_lower or "alibaba" in model_lower:
            # For Alibaba/Qwen, DashScope API requires thinking_budget >= 1 if passed as int,
            # so we only exclude reasoning tokens without setting max_tokens: 0 or effort: none
            pass
        elif "nvidia" in model_lower:
            reasoning_cfg["effort"] = "none"
            
        payload["reasoning"] = reasoning_cfg
        
        async with _shared_client() as client:
            response = await client.post(url, json=payload, headers=headers, timeout=120.0)
            if response.status_code != 200:
                print(f"[!] OpenRouter API Error ({response.status_code}): {response.text}")
                try:
                    err_json = response.json()
                    err_obj = err_json.get("error", {})
                    err_msg = err_obj.get("message", "")
                    # Extract detailed inner message if available from metadata
                    raw_meta = err_obj.get("metadata", {}).get("raw", "")
                    if "message" in raw_meta:
                        try:
                            # raw_meta can be "data: {...}\n\n" or JSON
                            clean_raw = raw_meta.replace("data:", "").strip()
                            inner_json = json.loads(clean_raw)
                            inner_msg = inner_json.get("error", {}).get("message")
                            if inner_msg:
                                err_msg = inner_msg
                        except Exception:
                            pass
                    
                    if response.status_code == 429:
                        raise ValueError(f"Model '{target_model}' is temporarily rate-limited upstream. Please retry shortly or select another model in Settings.")
                    elif response.status_code in [500, 502, 503, 504]:
                        raise ValueError(f"Model '{target_model}' is currently unavailable upstream ({response.status_code}). Please retry or choose another model.")
                    elif err_msg:
                        raise ValueError(f"{err_msg}")
                except ValueError:
                    raise
                except Exception:
                    pass
                response.raise_for_status()
            res_json = response.json()
            return res_json["choices"][0]["message"]["content"]

    async def _call_ollama(self, prompt: str, system_prompt: str, model: str = None, base_url: str = None) -> str:
        target_model = model or self.default_model
        ollama_url = base_url or self.ollama_base_url
        model_name = target_model.split("/")[-1]
        url = f"{ollama_url}/api/chat"
        
        payload = {
            "model": model_name,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": prompt}
            ],
            "stream": False
        }
        
        async with _shared_client() as client:
            response = await client.post(url, json=payload, timeout=120.0)
            response.raise_for_status()
            res_json = response.json()
            return res_json["message"]["content"]

