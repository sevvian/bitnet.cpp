# R5, R8: FastAPI application to wrap the bitnet.cpp inference engine.

import asyncio
import subprocess
import logging
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from typing import List

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class InferenceRequest(BaseModel):
    system_prompt: str = Field(..., description="The base prompt, including few-shot examples.")
    user_inputs: List[str] = Field(..., description="A list of user inputs to process.")
class InferenceResult(BaseModel):
    input: str
    output: str
class InferenceResponse(BaseModel):
    results: List[InferenceResult]

# --- Global Configuration ---
MODEL_PATH = "/app/models/ggml-model-i2_s.gguf"
INFERENCE_SCRIPT_PATH = "/app/run_inference.py"
# MODIFIED: Add path to our grammar file.
GRAMMAR_FILE_PATH = "/app/grammar/torrent_meta.gbnf"
NUM_THREADS = "4"
TEMPERATURE = "0.1" # Lower temperature for more deterministic JSON output
REPEAT_PENALTY = "1.1"

app = FastAPI(title="BitNet.cpp Inference API", description="An API to run batch inference on a BitNet GGUF model.", version="1.0.0")

async def run_inference_for_prompt(prompt: str) -> str:
    command = [
        "python",
        INFERENCE_SCRIPT_PATH,
        "-m", MODEL_PATH,
        "-p", prompt,
        "-t", NUM_THREADS,
        "-temp", TEMPERATURE,
        "--repeat-penalty", REPEAT_PENALTY,
        # MODIFIED: Use the grammar file to force valid JSON output.
        "--grammar-file", GRAMMAR_FILE_PATH,
        # Set a reasonable number of tokens to predict for a JSON object.
        "-n", "256",
        # Use a larger context size to prevent crashes.
        "-c", "2048",
    ]
    try:
        process = await asyncio.create_subprocess_exec(
            *command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        stdout, stderr = await process.communicate()
        if process.returncode != 0:
            error_message = stderr.decode().strip()
            logger.error(f"Inference script failed with code {process.returncode}: {error_message}")
            raise HTTPException(status_code=500, detail=f"Inference script error: {error_message}")
        full_output = stdout.decode().strip()
        
        prompt_cleaned = prompt.strip()
        output_cleaned = full_output.strip()
        if output_cleaned.startswith(prompt_cleaned):
            generated_text = output_cleaned[len(prompt_cleaned):].strip()
        else:
            generated_text = output_cleaned
        return generated_text
    except Exception as e:
        logger.error(f"An exception occurred during inference: {e}")
        raise e

@app.post("/api/v1/generate", response_model=InferenceResponse)
async def generate_batch(request: InferenceRequest):
    tasks = []
    for user_input in request.user_inputs:
        # Modified prompt format to better guide the model with grammar.
        full_prompt = f"{request.system_prompt.strip()}\nInput: {user_input.strip()}\nOutput:"
        tasks.append(run_inference_for_prompt(full_prompt))
    
    generated_outputs = await asyncio.gather(*tasks)
    results = [
        InferenceResult(input=inp, output=out)
        for inp, out in zip(request.user_inputs, generated_outputs)
    ]
    return InferenceResponse(results=results)

app.mount("/", StaticFiles(directory="/app/frontend", html=True), name="frontend")
