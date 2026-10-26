import json
import httpx
import os
import re
import engine_auth

def extract_markdown_from_payload(text: str) -> str:
    """
    Extract raw markdown documentation if the LLM outputted a function call or JSON wrapper,
    e.g. {"type": "function", "function": {"name": "propose_update", "parameters": {"content": "..."}}}
    """
    if not text:
        return ""
    text_stripped = text.strip()

    # If wrapped in markdown code blocks like ```json ... ```
    m_code = re.match(r"^```(?:json)?\s*(\{.*?\})\s*```$", text_stripped, re.DOTALL)
    candidate = m_code.group(1).strip() if m_code else text_stripped

    if candidate.startswith("{") and candidate.endswith("}"):
        try:
            parsed = json.loads(candidate)
            if isinstance(parsed, dict):
                # Shape 1: {"type": "function", "function": {"name": ..., "parameters": {"content": ...}}}
                func = parsed.get("function")
                if isinstance(func, dict):
                    params = func.get("parameters")
                    if isinstance(params, dict):
                        doc = params.get("content") or params.get("proposed_content") or params.get("markdown")
                        if doc and isinstance(doc, str):
                            return doc
                    elif isinstance(params, str):
                        try:
                            p_json = json.loads(params)
                            if isinstance(p_json, dict):
                                doc = p_json.get("content") or p_json.get("proposed_content")
                                if doc and isinstance(doc, str):
                                    return doc
                        except Exception:
                            pass

                # Shape 2: {"name": "propose_update", "parameters": {"content": ...}}
                params = parsed.get("parameters")
                if isinstance(params, dict):
                    doc = params.get("content") or params.get("proposed_content") or params.get("markdown")
                    if doc and isinstance(doc, str):
                        return doc
                elif isinstance(params, str):
                    try:
                        p_json = json.loads(params)
                        if isinstance(p_json, dict):
                            doc = p_json.get("content") or p_json.get("proposed_content")
                            if doc and isinstance(doc, str):
                                return doc
                    except Exception:
                        pass

                # Shape 3: {"content": "# ..."} or {"proposed_content": "# ..."}
                doc = parsed.get("content") or parsed.get("proposed_content") or parsed.get("markdown")
                if doc and isinstance(doc, str):
                    return doc
        except Exception:
            pass

    # Regex fallback if JSON was slightly malformed or truncated
    if '"content"' in text_stripped or '"proposed_content"' in text_stripped:
        m_regex = re.search(r'"(?:content|proposed_content)"\s*:\s*"((?:[^"\\]|\\.)*)"', text_stripped, re.DOTALL)
        if m_regex:
            try:
                decoded = json.loads(f'"{m_regex.group(1)}"')
                if decoded and len(decoded) > 50 and ("#" in decoded or "architecture" in decoded.lower()):
                    return decoded
            except Exception:
                pass

    return text

def clean_markdown_documentation(text: str) -> str:
    if not text:
        return ""
    
    # 0. Unpack any JSON function call / tool response wrapper
    text = extract_markdown_from_payload(text)
    
    # 1. Strip complete <think>...</think> and <thought>...</thought> blocks
    cleaned = re.sub(r"<(think|thought)>.*?</\1>", "", text, flags=re.DOTALL | re.IGNORECASE)
    
    # 2. Strip any stray opening/closing think/thought tags
    cleaned = re.sub(r"</?(think|thought)[^>]*>", "", cleaned, flags=re.IGNORECASE)
    
    # 3. Strip stray html tags like <br>, <br/>, <p>, </p>
    lines = cleaned.splitlines()
    filtered_lines = []
    for line in lines:
        stripped_line = line.strip()
        if re.match(r"^(<br\s*/?>|</?p>)+$", stripped_line, flags=re.IGNORECASE):
            continue
        filtered_lines.append(line)
    
    cleaned = "\n".join(filtered_lines).strip()
    
    # 4. If the model formatted the entire response as a Python comment block (# line 1, # line 2), un-comment it
    non_empty = [l for l in cleaned.splitlines() if l.strip()]
    if non_empty:
        comment_lines = [l for l in non_empty if l.startswith("# ") or l == "#"]
        if len(comment_lines) / len(non_empty) > 0.6:
            uncommented = []
            for l in cleaned.splitlines():
                if l.startswith("# "):
                    uncommented.append(l[2:])
                elif l == "#":
                    uncommented.append("")
                elif l.startswith("#"):
                    uncommented.append(l[1:])
                else:
                    uncommented.append(l)
            cleaned = "\n".join(uncommented).strip()

    # 5. If there is a markdown H1/H2 header, extract from the first header
    match = re.search(r"(?m)^(#{1,3}\s+[^\n]+)", cleaned)
    if match:
        cleaned = cleaned[match.start():]
    else:
        # If title line looks like a header without hash (e.g. Dicty Architecture Documentation...)
        title_match = re.search(r"(?m)^([A-Z0-9][^\n]+(?:Architecture|Documentation|Specification|Overview|Design)[^\n]*)", cleaned)
        if title_match:
            cleaned = "# " + cleaned[title_match.start():]

    # 6. Strip enclosing markdown code block wrapper if model wrapped whole document
    cleaned = re.sub(r"^```(?:markdown)?\s*\n", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\n```\s*$", "", cleaned)
    
    return cleaned.strip()

class AgentService:
    def __init__(self, provider: str, base_url: str, model: str, api_key: str):
        self.provider = provider
        self.model = model
        self.api_key = api_key
        
        if self.provider == "openrouter":
            self.base_url = "https://openrouter.ai/api/v1"
            if not self.api_key:
                self.api_key = os.getenv("OPENROUTER_API_KEY", "") or os.getenv("LLM_API_KEY", "")
            if not self.api_key:
                raise ValueError("OpenRouter requires an API Key. Please configure it in AI Integrations.")
        else:
            # Local endpoint
            self.base_url = base_url.rstrip('/')
            
            # Map localhost/127.0.0.1 to host.docker.internal for Docker networking
            if "127.0.0.1" in self.base_url or "localhost" in self.base_url:
                self.base_url = self.base_url.replace("127.0.0.1", "host.docker.internal").replace("localhost", "host.docker.internal")
            
            # Ensure the base url ends with /v1 for LM Studio / OpenAI compatibility
            if not self.base_url.endswith("/v1"):
                self.base_url += "/v1"
                
            if not self.api_key:
                self.api_key = "dummy" # Some local servers need a non-empty string

    async def run_agent_loop(self, system_prompt: str, user_prompt: str, tools_funcs: dict, max_steps: int = 12) -> dict:
        """
        Runs an Agent loop with the given prompts and tool implementations.
        tools_funcs: dict of { "tool_name": (schema_dict, python_callable) }
        Returns the final proposed_update args (path, content).
        """
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt}
        ]
        
        tools = []
        for name, (schema, _) in tools_funcs.items():
            tools.append({
                "type": "function",
                "function": schema
            })
            
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://github.com/vkazmin/dicty",
        }
        
        url = f"{self.base_url}/chat/completions"
        
        propose_tool = None
        for t in tools:
            if t.get("function", {}).get("name") == "propose_update":
                propose_tool = t
                break

        files_read = 0

        async with httpx.AsyncClient(timeout=60.0) as client:
            for step in range(max_steps):
                payload = {
                    "model": self.model,
                    "messages": messages,
                    "tools": tools,
                    "tool_choice": "auto"
                }
                
                print(f"[Agent] Step {step+1}/{max_steps}: Exploring repository with {self.model} ...")
                fallback_models = [self.model, "qwen/qwen-2.5-coder-32b-instruct", "qwen/qwen3.7-plus", "openai/gpt-4o-mini", "deepseek/deepseek-chat"]
                unique_models = []
                for m in fallback_models:
                    if m and m not in unique_models:
                        unique_models.append(m)

                message = None
                last_err = ""

                for model_candidate in unique_models:
                    payload["model"] = model_candidate
                    try:
                        resp = await client.post(url, json=payload, headers=headers, timeout=35.0)
                        if resp.status_code != 200:
                            try:
                                err_data = resp.json()
                                last_err = err_data.get("error", {}).get("message", resp.text)
                            except Exception:
                                last_err = resp.text
                            print(f"[Agent] Model '{model_candidate}' returned HTTP {resp.status_code}: {last_err}")
                            continue

                        res_json = resp.json()
                        if "error" in res_json or "choices" not in res_json or not res_json["choices"]:
                            last_err = str(res_json.get("error", {}).get("message", resp.text))
                            print(f"[Agent] Model '{model_candidate}' returned error payload: {last_err}")
                            continue

                        message = res_json["choices"][0]["message"]
                        self.model = model_candidate
                        break
                    except Exception as call_err:
                        last_err = str(call_err)
                        print(f"[Agent] Request to '{model_candidate}' failed: {call_err}")
                        continue

                if not message:
                    break

                messages.append(message)
                
                if message.get("tool_calls"):
                    for tool_call in message["tool_calls"]:
                        func_name = tool_call["function"]["name"]
                        args_str = tool_call["function"]["arguments"]
                        
                        try:
                            args = json.loads(args_str)
                        except Exception:
                            args = {}
                            
                        print(f"[Agent] Calling tool: {func_name}")
                        for host in ["127.0.0.1:8075", "host.docker.internal:8075"]:
                            try:
                                req_headers = dict(engine_auth.auth_headers())
                                if "host.docker.internal" in host:
                                    req_headers["Host"] = "127.0.0.1:8075"
                                async with httpx.AsyncClient() as c:
                                    await c.post(f"http://{host}/recording/status/update", json={"status": f"Agent executing: {func_name}..."}, headers=req_headers, timeout=0.5)
                                    break
                            except Exception:
                                pass

                        if func_name == "propose_update":
                            return args
                            
                        if func_name in tools_funcs:
                            _, func_callable = tools_funcs[func_name]
                            try:
                                import inspect
                                if inspect.iscoroutinefunction(func_callable):
                                    result = await func_callable(**args)
                                else:
                                    result = func_callable(**args)
                            except Exception as e:
                                result = f"Error: {str(e)}"
                        else:
                            result = f"Error: Tool {func_name} not found."
                            
                        if func_name == "read_repo_file":
                            files_read += 1

                        print(f"[Agent] Tool result: {str(result)[:150]}...")
                        
                        messages.append({
                            "role": "tool",
                            "tool_call_id": tool_call["id"],
                            "name": func_name,
                            "content": str(result)[:2500]
                        })

                    # If the agent has read 3 or more files, break loop and proceed directly to synthesis
                    if files_read >= 3:
                        print(f"[Agent] Explored {files_read} key codebase files. Transitioning to final synthesis...")
                        break
                else:
                    content = (message.get("content") or "").strip()
                    if content and len(content) > 100:
                        print("[Agent] LLM provided direct documentation content. Finalizing update.")
                        return {
                            "proposed_content": clean_markdown_documentation(content)
                        }
                    break

            # Phase 2: Direct Document Synthesis
            print("[Agent] Synthesizing comprehensive ARCHITECTURE.md markdown documentation...")
            for host in ["127.0.0.1:8075", "host.docker.internal:8075"]:
                try:
                    req_headers = dict(engine_auth.auth_headers())
                    if "host.docker.internal" in host:
                        req_headers["Host"] = "127.0.0.1:8075"
                    async with httpx.AsyncClient() as c:
                        await c.post(f"http://{host}/recording/status/update", json={"status": "Agent synthesizing final documentation..."}, headers=req_headers, timeout=0.5)
                        break
                except Exception:
                    pass

            inspected_context = []
            for m in messages:
                if m.get("role") == "tool":
                    content_snippet = (m.get("content") or "").strip()
                    if content_snippet and len(content_snippet) > 10:
                        inspected_context.append(content_snippet[:2500])

            context_block = "\n\n---\n\n".join(inspected_context)
            synthesis_prompt = f"{user_prompt}\n\nHere are the inspected key files and project structure from the repository:\n\n{context_block}\n\nSynthesize and output the final, complete ARCHITECTURE.md markdown documentation now with full Markdown tables and component breakdowns. Do not include internal monologue or thought tags in your output."

            final_messages = [
                {
                    "role": "system",
                    "content": system_prompt
                },
                {
                    "role": "user",
                    "content": synthesis_prompt[:25000]
                }
            ]

            fallback_candidates = [self.model, "qwen/qwen-2.5-coder-32b-instruct", "google/gemini-2.5-flash", "openai/gpt-4o-mini", "deepseek/deepseek-chat"]
            unique_candidates = []
            for c in fallback_candidates:
                if c and c not in unique_candidates:
                    unique_candidates.append(c)

            for model_candidate in unique_candidates:
                try:
                    final_resp = await client.post(
                        url,
                        json={"model": model_candidate, "messages": final_messages},
                        headers=headers,
                        timeout=120.0
                    )
                    if final_resp.status_code == 200:
                        data = final_resp.json()
                        final_text = (data.get("choices", [{}])[0].get("message", {}).get("content") or "").strip()
                        cleaned = clean_markdown_documentation(final_text)
                        is_tool_call_garbage = "<tool_call" in cleaned.lower() or "<function=" in cleaned.lower()
                        if cleaned and len(cleaned) > 200 and ("#" in cleaned or "architecture" in cleaned.lower()) and not is_tool_call_garbage:
                            return {"proposed_content": cleaned}
                        else:
                            print(f"[Agent] Model '{model_candidate}' generated shallow or incomplete draft ({len(cleaned)} chars). Trying fallback candidate...")
                except Exception as e:
                    print(f"[Agent] Synthesis on '{model_candidate}' failed: {e}")
                    continue

            raise Exception("Failed to synthesize valid documentation across all available model candidates.")
