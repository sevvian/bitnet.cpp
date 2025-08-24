// R9: Frontend JavaScript logic

document.addEventListener('DOMContentLoaded', () => {
    // --- Element References ---
    const themeSelector = document.getElementById('theme');
    const systemPromptEl = document.getElementById('system-prompt');
    const batchInputEl = document.getElementById('batch-input');
    const parseButton = document.getElementById('parse-button');
    const loader = document.getElementById('loader');
    const resultsContainer = document.getElementById('results-container');
    const toggleAllButton = document.getElementById('toggle-all-button');

    // --- Default Prompts ---
    // R9.1: Provide a default few-shot system prompt for the user.
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


    // --- Theme Switcher Logic (R9.7) ---
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
        // R9.2: Get batch inputs, filter out empty lines.
        const userInputs = batchInputEl.value.trim().split('\n').filter(line => line.trim() !== '');

        if (!systemPrompt || userInputs.length === 0) {
            alert('Please provide a system prompt and at least one torrent title.');
            return;
        }

        // R9.3: Trigger API call
        setLoading(true);

        try {
            const response = await fetch('/api/v1/generate', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ system_prompt: systemPrompt, user_inputs: userInputs }),
            });

            if (!response.ok) {
                const error = await response.json();
                throw new Error(error.detail || 'An unknown error occurred.');
            }

            const data = await response.json();
            displayResults(data.results);

        } catch (error) {
            resultsContainer.innerHTML = `<p class="placeholder" style="color: red;">Error: ${error.message}</p>`;
        } finally {
            setLoading(false);
        }
    };

    const setLoading = (isLoading) => {
        if (isLoading) {
            parseButton.disabled = true;
            loader.classList.remove('hidden');
            resultsContainer.innerHTML = '<p class="placeholder">Parsing... this may take a moment.</p>';
        } else {
            parseButton.disabled = false;
            loader.classList.add('hidden');
        }
    };
    
    // R9.5: Display results in the specified format
    const displayResults = (results) => {
        resultsContainer.innerHTML = ''; // Clear previous results
        if (results.length === 0) {
            resultsContainer.innerHTML = '<p class="placeholder">No results to display.</p>';
            toggleAllButton.disabled = true;
            return;
        }

        toggleAllButton.disabled = false;
        results.forEach(result => {
            const resultItem = document.createElement('div');
            resultItem.className = 'result-item';

            // Attempt to parse and format the JSON output
            let formattedOutput = result.output;
            try {
                const jsonObj = JSON.parse(result.output);
                formattedOutput = JSON.stringify(jsonObj, null, 2);
            } catch (e) {
                // Not valid JSON, display as is.
            }

            resultItem.innerHTML = `
                <div class="result-item-header">
                    <span class="result-item-title">${result.input}</span>
                    <button class="visibility-toggle" data-action="toggle-one">Hide</button>
                </div>
                <div class="result-item-body">
                    <pre><code>${formattedOutput}</code></pre>
                </div>
            `;
            resultsContainer.appendChild(resultItem);
        });
    };
    
    // --- Event Listeners ---
    parseButton.addEventListener('click', handleParse);

    // R9.5 & R9.6: Event delegation for individual and global toggles
    resultsContainer.addEventListener('click', (e) => {
        if (e.target && e.target.dataset.action === 'toggle-one') {
            const button = e.target;
            const body = button.closest('.result-item').querySelector('.result-item-body');
            const isHidden = body.style.display === 'none';
            body.style.display = isHidden ? '' : 'none';
            button.textContent = isHidden ? 'Hide' : 'Show';
        }
    });

    toggleAllButton.addEventListener('click', () => {
        const bodies = resultsContainer.querySelectorAll('.result-item-body');
        const buttons = resultsContainer.querySelectorAll('[data-action="toggle-one"]');
        if (bodies.length === 0) return;

        // Determine state based on the first item
        const shouldHide = bodies[0].style.display !== 'none';
        
        bodies.forEach(body => body.style.display = shouldHide ? 'none' : '');
        buttons.forEach(button => button.textContent = shouldHide ? 'Show' : 'Hide');
    });
});
