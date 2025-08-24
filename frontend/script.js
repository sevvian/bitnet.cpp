// R9: Frontend JavaScript logic

document.addEventListener('DOMContentLoaded', () => {
    // ... (Element References and Default Prompts are unchanged) ...
    const themeSelector = document.getElementById('theme');
    const systemPromptEl = document.getElementById('system-prompt');
    const batchInputEl = document.getElementById('batch-input');
    const parseButton = document.getElementById('parse-button');
    const loader = document.getElementById('loader');
    const resultsContainer = document.getElementById('results-container');
    const toggleAllButton = document.getElementById('toggle-all-button');
    const DEFAULT_SYSTEM_PROMPT = `You are an expert torrent metadata extractor. Your task is to extract information from a torrent title and return it as a structured JSON object. The JSON object should contain the following fields: 'title', 'year', 'resolution', 'source', 'codec', 'audio', and 'group'. If a field is not present, use a null value.

Here are some examples:

Input: The.Matrix.1999.1080p.BluRay.x264-FLAWLESS
Output:
{
  "title": "The Matrix",
  "year": 1999,
  "resolution": "1080p",
  "source": "BluRay",
  "codec": "x264",
  "audio": null,
  "group": "FLAWLESS"
}

Input: Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.x265-CM
Output:
{
  "title": "Dune Part Two",
  "year": 2024,
  "resolution": "2160p",
  "source": "WEB-DL",
  "codec": "x265",
  "audio": "DDP5.1 Atmos",
  "group": "CM"
}

Now, extract the metadata for the following input. Only return the JSON object, nothing else.

Input:`;
    systemPromptEl.value = DEFAULT_SYSTEM_PROMPT;

    // ... (Theme switcher logic is unchanged) ...
    const applyTheme = (theme) => {
        if (theme === 'system') {
            const systemTheme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
            document.documentElement.setAttribute('data-theme', systemTheme);
        } else {
            document.documentElement.setAttribute('data-theme', theme);
        }
        localStorage.setItem('theme', theme);
        themeSelector.value = theme;
    };
    const currentTheme = localStorage.getItem('theme') || 'system';
    applyTheme(currentTheme);
    themeSelector.addEventListener('change', (e) => applyTheme(e.target.value));
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
        if (localStorage.getItem('theme') === 'system') {
            applyTheme('system');
        }
    });

    // --- API Call and Results Logic ---
    const handleParse = async () => {
        const systemPrompt = systemPromptEl.value.trim();
        const userInputs = batchInputEl.value.trim().split('\n').filter(line => line.trim() !== '');

        if (!systemPrompt || userInputs.length === 0) {
            alert('Please provide a system prompt and at least one torrent title.');
            return;
        }

        setLoading(true);

        try {
            const response = await fetch('/api/v1/generate', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ system_prompt: systemPrompt, user_inputs: userInputs }),
            });

            // --- THIS IS THE CRITICAL MODIFICATION ---
            // If the response is not OK (e.g., a 500 error), read it as text and throw an error.
            if (!response.ok) {
                const errorText = await response.text();
                // We try to parse it as JSON to get the detailed message from FastAPI
                try {
                    const errorJson = JSON.parse(errorText);
                    throw new Error(`${response.status}: ${errorJson.detail || 'An unknown error occurred.'}`);
                } catch (e) {
                    // If it's not JSON (e.g., raw HTML), throw the raw text.
                    throw new Error(`${response.status}: ${errorText}`);
                }
            }
            // --- END OF MODIFICATION ---

            const data = await response.json();
            displayResults(data.results);

        } catch (error) {
            // The error message will now contain the detailed C++ error.
            resultsContainer.innerHTML = `<p class="placeholder" style="color: red; white-space: pre-wrap;">${error.message}</p>`;
        } finally {
            setLoading(false);
        }
    };

    // ... (setLoading and displayResults logic is unchanged) ...
    const setLoading = (isLoading) => { /*...*/ };
    const displayResults = (results) => { /*...*/ };
    
    // ... (Event Listeners are unchanged) ...
    parseButton.addEventListener('click', handleParse);
    resultsContainer.addEventListener('click', (e) => { /*...*/ });
    toggleAllButton.addEventListener('click', () => { /*...*/ });
});
