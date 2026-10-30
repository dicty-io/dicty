current_processing_status = "Idle"

def set_status(msg: str):
    global current_processing_status
    current_processing_status = msg
    print(f"[Status] {msg}")


active_websockets = []

async def broadcast_partial_transcription(text: str):
    for ws in active_websockets:
        try:
            await ws.send_json({
                "status": "partial",
                "text": text
            })
        except:
            pass
