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
        # Redirect stderr to stdout to capture all output from llama-cli
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
    
    # MODIFIED: Increased default context size to prevent crashes with long prompts.
    parser.add_argument('-c', '--ctx-size', type=int, default=2048, help='Size of the prompt context')
    
    parser.add_argument('-temp', '--temperature', type=float, default=0.8, help='Temperature for sampling')
    parser.add_argument('--repeat-penalty', type=float, default=1.1, help='Repetition penalty')
    
    # MODIFIED: Added argument for GBNF grammar file.
    parser.add_argument('--grammar-file', type=str, help='Path to GBNF grammar file')

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
        "--repeat-penalty", str(args.repeat_penalty),
    ]

    # MODIFIED: Add grammar file to command if provided.
    if args.grammar_file:
        command.extend(["--grammar-file", args.grammar_file])

    if args.conversation:
        command.extend(["--conversation"])

    run_command(command)

if __name__ == "__main__":
    run_inference()
