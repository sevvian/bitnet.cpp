#
# MODIFIED FOR PRODUCTION CONTAINER
# This script is designed to run inside our container and uses absolute paths.
#
import subprocess
import argparse
import sys

def run_command(command, shell=False):
    """Run a system command and ensure it succeeds."""
    try:
        subprocess.run(command, shell=shell, check=True, stdout=sys.stdout, stderr=sys.stderr)
    except subprocess.CalledProcessError as e:
        print(f"Error occurred while running command: {e}")
        raise e

def run_inference():
    parser = argparse.ArgumentParser(description='Run inference')
    parser.add_argument('-m', '--model', type=str, required=True, help='Path to model file')
    parser.add_argument('-n', '--n-predict', type=int, default=128, help='Number of tokens to predict')
    parser.add_argument('-p', '--prompt', type=str, required=True, help='Prompt to generate text from')
    parser.add_argument('-t', '--threads', type=int, default=4, help='Number of threads to use')
    parser.add_argument('-c', '--ctx-size', type=int, default=512, help='Size of the prompt context')
    parser.add_argument('-temp', '--temperature', type=float, default=0.8, help='Temperature for sampling')
    parser.add_argument('-cnv', '--conversation', action='store_true', help='Enable conversation mode')
    args = parser.parse_args()

    # --- THIS IS THE CRITICAL MODIFICATION ---
    # The executable will be in /app/bin/, a clean location.
    executable_path = "/app/bin/llama-cli"
    # --- END OF MODIFICATION ---

    command = [
        executable_path,
        "-m", args.model,
        "-n", str(args.n_predict),
        "-p", args.prompt,
        "--temp", str(args.temperature),
        "-c", str(args.ctx_size),
        "-t", str(args.threads),
    ]

    if args.conversation:
        command.extend(["--conversation"])

    run_command(command)

if __name__ == "__main__":
    run_inference()
