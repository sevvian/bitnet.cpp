#
# MODIFIED FOR PRODUCTION CONTAINER
# This is a modified version of the original run_inference.py from the BitNet repository.
# The path to the executable has been changed to an absolute path for our container.
#
import subprocess
import argparse
import sys

def run_command(command, shell=False):
    """Run a system command and ensure it succeeds."""
    try:
        # Redirect stderr to stdout to capture all output from llama-cli
        subprocess.run(command, shell=shell, check=True, stdout=sys.stdout, stderr=subprocess.STDOUT)
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
    
    # --- THIS IS THE CRITICAL MODIFICATION ---
    # Add the repeat_penalty argument, which is crucial for preventing output loops.
    parser.add_argument('--repeat-penalty', type=float, default=1.1, help='Repetition penalty')
    # --- END OF MODIFICATION ---

    parser.add_argument('-cnv', '--conversation', action='store_true', help='Enable conversation mode')
    args = parser.parse_args()

    executable_path = "/app/build/bin/llama-cli"

    command = [
        executable_path,
        "-m", args.model,
        "-n", str(args.n_predict),
        "-p", args.prompt,
        "--temp", str(args.temperature),
        "-c", str(args.ctx_size),
        "-t", str(args.threads),
        # --- THIS IS THE CRITICAL MODIFICATION ---
        # Add the repeat penalty flag to the command sent to the C++ executable.
        "--repeat-penalty", str(args.repeat_penalty),
        # --- END OF MODIFICATION ---
    ]

    if args.conversation:
        # For conversation mode, it's good to use a larger context
        command.extend(["-c", "2048", "--conversation"])

    run_command(command)

if __name__ == "__main__":
    run_inference()
