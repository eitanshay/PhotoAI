# polish (ES-07)

Pick a photo, Gemini reads it, writes a genre-specific retouch brief, and a Gemini image model regenerates it with the subject kept.

Run locally: `python3 -m http.server 8000` then open http://localhost:8000
Phone: host the folder on any HTTPS static host (Netlify Drop, GitHub Pages, Cloudflare Pages), open it in Safari, Share, Add to Home Screen.
Key: paste your Gemini API key in Settings. It is stored in this browser only.
Models: defaults gemini-3.8-flash (brief) and gemini-3.1-flash-image (edit). Change them in Settings if Google renames them.
