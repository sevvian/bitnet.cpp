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

# --- Pydantic Models for API data validation ---
class InferenceRequest(BaseModel):
    """Defines the structure for a batch inference request."""
    system_prompt: str = Field(..., description="The base prompt, including few-shot examples.")
    user_inputs: List[str] = Field(..., description="A list of user inputs to process.")

class InferenceResult(BaseModel):
    """Defines the structure for a single inference result."""
    input: str
    output: str

class InferenceResponse(BaseModel):
    """Defines the structure for the complete batch response."""
    results: List[InferenceResult]

# --- Global Configuration ---
# R4: Path to the model inside the container.
MODEL_PATH = "/app/models/BitNet-b1.58-2B-4T-gguf/ggml-model-i2_s.gguf"
INFERENCE_SCRIPT_PATH = "/app/run_inference.py"
# R6: Number of threads to use for inference. Adjust based on N5105 capabilities (4 cores, 4 threads).
NUM_THREADS = "4"

# --- FastAPI App Initialization ---
app = FastAPI(
    title="BitNet.cpp Inference API",
    description="An API to run batch inference on a BitNet GGUF model.",
    version="1.0.0",
)

# --- Core Inference Logic ---
async def run_inference_for_prompt(prompt: str) -> str:
    """
    R5: Executes the bitnet.cpp inference script for a single prompt.
    Runs the synchronous subprocess in a separate thread to avoid blocking the asyncio event loop.
    """
    command = [
        "python",
        INFERENCE_SCRIPT_PATH,
        "-m", MODEL_PATH,
        "-p", prompt,
        "-t", NUM_THREADS,
    ]

    try:
        # R8.1: Use asyncio.create_subprocess_exec for non-blocking execution
        process = await asyncio.create_subprocess_exec(
            *command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        stdout, stderr = await process.communicate()

        if process.returncode != 0:
            error_message = stderr.decode().strip()
            logger.error(f"Inference process failed with code {process.returncode}: {error_message}")
            raise HTTPException(status_code=500, detail=f"Inference script error: {error_message}")

        full_output = stdout.decode().strip()
        
        # The script echoes the prompt. We need to parse the output to isolate the generation.
        # A simple and robust way is to find the generated text that follows the prompt.
        if prompt in full_output:
            # Take the content after the last occurrence of the prompt
            generated_text = full_output.rsplit(prompt, 1)[-1].strip()
        else:
            # Fallback if prompt echoing behavior changes
            generated_text = full_output

        return generated_text

    except Exception as e:
        logger.error(f"An exception occurred during inference: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- API Endpoints ---
@app.post("/api/v1/generate", response_model=InferenceResponse)
async def generate_batch(request: InferenceRequest):
    """
    R8.1: API endpoint to handle batch inference requests.
    It combines the system prompt with each user input and runs inference concurrently.
    """
    tasks = []
    for user_input in request.user_inputs:
        # R9.4: Combine system prompt with user input
        full_prompt = f"{request.system_prompt.strip()}\n{user_input.strip()}"
        tasks.append(run_inference_for_prompt(full_prompt))
    
    # Run all inference tasks concurrently
    generated_outputs = await asyncio.gather(*tasks)

    # Structure the results
    results = [
        InferenceResult(input=inp, output=out)
        for inp, out in zip(request.user_inputs, generated_outputs)
    ]

    return InferenceResponse(results=results)

# R9: Mount the frontend directory to serve static files (index.html, css, js).
# The root path "/" will serve the main frontend page.
app.mount("/", StaticFiles(directory="/app/frontend", html=True), name="frontend")
