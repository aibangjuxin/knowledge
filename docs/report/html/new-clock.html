<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Team Time Zone Clock</title>
    <link rel="icon" href="https://vectorcraftr.com/library/blink/Young%20woman%20with%20headphones.svg" type="image/svg+xml" />
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
    <style>
      /* ============================================================
         Design tokens — modern minimal, Notion/Linear/Vercel adjacent
         Light is the default; .dark-mode toggles the alternate set.
         ============================================================ */
      :root {
        --bg: #fafafa;
        --bg-elevated: #ffffff;
        --bg-subtle: #f4f4f5;
        --bg-overlay: rgba(255, 255, 255, 0.8);
        --border: #e4e4e7;
        --border-strong: #d4d4d8;

        --text-primary: #18181b;
        --text-secondary: #52525b;
        --text-muted: #a1a1aa;
        --text-inverse: #fafafa;

        --accent: #18181b;
        --accent-hover: #27272a;
        --accent-text: #fafafa;
        --focus-ring: rgba(24, 24, 27, 0.12);

        --status-working: #16a34a;
        --status-working-bg: #dcfce7;
        --status-off: #dc2626;
        --status-off-bg: #fee2e2;
        --status-current: #ea580c;
        --status-current-bg: #ffedd5;

        --radius-sm: 6px;
        --radius-md: 8px;
        --radius-lg: 12px;

        --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.04);
        --shadow-md: 0 1px 3px rgba(0, 0, 0, 0.06), 0 1px 2px rgba(0, 0, 0, 0.04);
        --shadow-lg: 0 4px 6px -1px rgba(0, 0, 0, 0.06), 0 2px 4px -2px rgba(0, 0, 0, 0.04);

        --font-sans: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        --font-mono: 'JetBrains Mono', 'SF Mono', 'Monaco', 'Inconsolata', 'Roboto Mono', monospace;

        --transition: 150ms cubic-bezier(0.16, 1, 0.3, 1);
      }

      .dark-mode {
        --bg: #0a0a0a;
        --bg-elevated: #111113;
        --bg-subtle: #18181b;
        --bg-overlay: rgba(17, 17, 19, 0.85);
        --border: #27272a;
        --border-strong: #3f3f46;

        --text-primary: #fafafa;
        --text-secondary: #a1a1aa;
        --text-muted: #71717a;
        --text-inverse: #0a0a0a;

        --accent: #fafafa;
        --accent-hover: #e4e4e7;
        --accent-text: #0a0a0a;
        --focus-ring: rgba(250, 250, 250, 0.18);

        --status-working: #4ade80;
        --status-working-bg: rgba(74, 222, 128, 0.12);
        --status-off: #f87171;
        --status-off-bg: rgba(248, 113, 113, 0.12);
        --status-current: #fb923c;
        --status-current-bg: rgba(251, 146, 60, 0.12);

        --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.3);
        --shadow-md: 0 1px 3px rgba(0, 0, 0, 0.4), 0 1px 2px rgba(0, 0, 0, 0.3);
        --shadow-lg: 0 4px 6px -1px rgba(0, 0, 0, 0.4), 0 2px 4px -2px rgba(0, 0, 0, 0.3);
      }

      * { margin: 0; padding: 0; box-sizing: border-box; }

      html { font-size: 16px; }

      body {
        font-family: var(--font-sans);
        background: var(--bg);
        color: var(--text-primary);
        min-height: 100vh;
        display: flex;
        flex-direction: column;
        align-items: center;
        padding: 32px 24px 96px;
        line-height: 1.5;
        -webkit-font-smoothing: antialiased;
        -moz-osx-font-smoothing: grayscale;
        transition: background-color var(--transition), color var(--transition);
      }

      /* Skip-link for keyboard users */
      .skip-link {
        position: absolute;
        left: -9999px;
        top: 0;
        background: var(--accent);
        color: var(--accent-text);
        padding: 8px 12px;
        border-radius: var(--radius-sm);
        z-index: 100;
      }
      .skip-link:focus { left: 16px; top: 16px; }

      /* ============================================================
         Layout shell
         ============================================================ */
      .page {
        width: 100%;
        max-width: 1280px;
        display: flex;
        flex-direction: column;
        gap: 24px;
      }

      /* ============================================================
         Header
         ============================================================ */
      .header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 24px;
        flex-wrap: wrap;
      }
      .header-titles h1 {
        font-size: 1.75rem;
        font-weight: 700;
        letter-spacing: -0.02em;
        color: var(--text-primary);
        margin-bottom: 4px;
      }
      .header-titles p {
        font-size: 0.9375rem;
        color: var(--text-secondary);
      }

      /* ============================================================
         Theme toggle — top right pill
         ============================================================ */
      .theme-toggle {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        padding: 8px 14px;
        background: var(--bg-elevated);
        color: var(--text-primary);
        border: 1px solid var(--border);
        border-radius: 999px;
        font-family: inherit;
        font-size: 0.8125rem;
        font-weight: 500;
        cursor: pointer;
        transition: all var(--transition);
        box-shadow: var(--shadow-sm);
      }
      .theme-toggle:hover {
        background: var(--bg-subtle);
        border-color: var(--border-strong);
      }
      .theme-toggle:focus-visible {
        outline: 2px solid var(--accent);
        outline-offset: 2px;
      }
      .theme-toggle i { font-size: 0.875rem; }

      /* ============================================================
         Search
         ============================================================ */
      .search-container {
        position: relative;
        width: 100%;
      }
      .search-box {
        width: 100%;
        padding: 12px 16px 12px 44px;
        background: var(--bg-elevated);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        color: var(--text-primary);
        font-family: inherit;
        font-size: 0.9375rem;
        transition: all var(--transition);
        box-shadow: var(--shadow-sm);
      }
      .search-box::placeholder { color: var(--text-muted); }
      .search-box:focus {
        outline: none;
        border-color: var(--accent);
        box-shadow: 0 0 0 4px var(--focus-ring);
      }
      .search-container > i {
        position: absolute;
        left: 16px;
        top: 50%;
        transform: translateY(-50%);
        color: var(--text-muted);
        font-size: 0.875rem;
        pointer-events: none;
      }

      /* ============================================================
         Stats bar
         ============================================================ */
      .stats-bar {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 1px;
        background: var(--border);
        border: 1px solid var(--border);
        border-radius: var(--radius-lg);
        overflow: hidden;
        box-shadow: var(--shadow-sm);
      }
      .stat-item {
        background: var(--bg-elevated);
        padding: 20px;
        display: flex;
        flex-direction: column;
        gap: 6px;
        transition: background-color var(--transition);
      }
      .stat-item:hover { background: var(--bg-subtle); }
      .stat-number {
        font-family: var(--font-mono);
        font-size: 1.5rem;
        font-weight: 600;
        color: var(--text-primary);
        letter-spacing: -0.02em;
      }
      .stat-label {
        font-size: 0.75rem;
        font-weight: 500;
        color: var(--text-muted);
        text-transform: uppercase;
        letter-spacing: 0.04em;
      }

      /* ============================================================
         Two-column main
         ============================================================ */
      .main-content {
        display: grid;
        grid-template-columns: minmax(320px, 1fr) minmax(0, 2fr);
        gap: 24px;
      }
      .left-column, .right-column {
        display: flex;
        flex-direction: column;
        gap: 24px;
        min-width: 0;
      }

      /* ============================================================
         Card — shared shell for calendar / sidebar / clock card
         ============================================================ */
      .card {
        background: var(--bg-elevated);
        border: 1px solid var(--border);
        border-radius: var(--radius-lg);
        padding: 24px;
        box-shadow: var(--shadow-sm);
        transition: border-color var(--transition), box-shadow var(--transition);
      }
      .card:hover {
        border-color: var(--border-strong);
        box-shadow: var(--shadow-md);
      }
      .card-title {
        display: flex;
        align-items: center;
        gap: 10px;
        font-size: 0.9375rem;
        font-weight: 600;
        color: var(--text-primary);
        margin-bottom: 20px;
        letter-spacing: -0.01em;
      }
      .card-title i {
        color: var(--text-muted);
        font-size: 0.875rem;
      }

      /* ============================================================
         Calendar
         ============================================================ */
      .calendar-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 16px;
      }
      .calendar-title-block h3 {
        font-size: 1.0625rem;
        font-weight: 600;
        color: var(--text-primary);
        letter-spacing: -0.01em;
      }
      .calendar-title-block p {
        font-size: 0.8125rem;
        color: var(--text-muted);
        margin-top: 2px;
      }
      .nav-btn {
        width: 32px;
        height: 32px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        background: var(--bg-elevated);
        border: 1px solid var(--border);
        border-radius: var(--radius-sm);
        color: var(--text-secondary);
        cursor: pointer;
        transition: all var(--transition);
      }
      .nav-btn:hover {
        background: var(--bg-subtle);
        color: var(--text-primary);
        border-color: var(--border-strong);
      }
      .nav-btn:focus-visible {
        outline: 2px solid var(--accent);
        outline-offset: 2px;
      }
      .nav-btn i { font-size: 0.75rem; }

      .weekdays {
        display: grid;
        grid-template-columns: repeat(7, 1fr);
        gap: 4px;
        margin-bottom: 8px;
      }
      .weekday {
        text-align: center;
        font-size: 0.6875rem;
        font-weight: 600;
        color: var(--text-muted);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        padding: 8px 0;
      }
      .days-grid {
        display: grid;
        grid-template-columns: repeat(7, 1fr);
        gap: 4px;
      }
      .day {
        aspect-ratio: 1;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 0.8125rem;
        font-weight: 500;
        color: var(--text-primary);
        background: transparent;
        border: 1px solid transparent;
        border-radius: var(--radius-sm);
        cursor: pointer;
        transition: all var(--transition);
      }
      .day:hover {
        background: var(--bg-subtle);
        border-color: var(--border);
      }
      .day:focus-visible {
        outline: 2px solid var(--accent);
        outline-offset: -2px;
      }
      .day.other-month { color: var(--text-muted); opacity: 0.45; }
      .day.today {
        background: var(--accent);
        color: var(--accent-text);
        font-weight: 600;
      }
      .day.today:hover { background: var(--accent-hover); }
      .day.selected {
        background: var(--bg-subtle);
        border-color: var(--accent);
        font-weight: 600;
      }

      .calendar-footer {
        margin-top: 16px;
        padding-top: 16px;
        border-top: 1px solid var(--border);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }
      .today-label {
        font-size: 0.75rem;
        color: var(--text-muted);
        text-transform: uppercase;
        letter-spacing: 0.04em;
        font-weight: 500;
      }
      .today-date {
        font-size: 0.8125rem;
        color: var(--text-primary);
        font-weight: 500;
      }

      /* ============================================================
         Timezone converter
         ============================================================ */
      .converter-form {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .converter-input,
      .form-input,
      .form-select {
        width: 100%;
        padding: 10px 12px;
        background: var(--bg-elevated);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        color: var(--text-primary);
        font-family: inherit;
        font-size: 0.875rem;
        transition: all var(--transition);
      }
      .form-select[multiple] { min-height: 120px; }
      .converter-input:focus,
      .form-input:focus,
      .form-select:focus {
        outline: none;
        border-color: var(--accent);
        box-shadow: 0 0 0 4px var(--focus-ring);
      }
      .submit-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
        padding: 10px 16px;
        background: var(--accent);
        color: var(--accent-text);
        border: 1px solid var(--accent);
        border-radius: var(--radius-md);
        font-family: inherit;
        font-size: 0.875rem;
        font-weight: 500;
        cursor: pointer;
        transition: all var(--transition);
      }
      .submit-btn:hover {
        background: var(--accent-hover);
        border-color: var(--accent-hover);
      }
      .submit-btn:focus-visible {
        outline: 2px solid var(--accent);
        outline-offset: 2px;
      }
      .submit-btn i { font-size: 0.8125rem; }

      .converter-result {
        margin-top: 4px;
        padding: 14px 16px;
        background: var(--bg-subtle);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        font-size: 0.875rem;
        color: var(--text-secondary);
        line-height: 1.5;
      }
      .converter-result strong {
        display: block;
        font-size: 0.6875rem;
        font-weight: 600;
        color: var(--text-muted);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        margin-bottom: 6px;
      }
      .converter-result .converted-time {
        font-family: var(--font-mono);
        font-size: 1rem;
        font-weight: 600;
        color: var(--text-primary);
        margin-bottom: 6px;
      }
      .converter-result .converted-route {
        font-size: 0.75rem;
        color: var(--text-muted);
      }

      /* ============================================================
         Clock cards
         ============================================================ */
      .clock-container {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
        gap: 16px;
      }
      .clock-card {
        background: var(--bg-elevated);
        border: 1px solid var(--border);
        border-radius: var(--radius-lg);
        padding: 20px;
        box-shadow: var(--shadow-sm);
        transition: all var(--transition);
        position: relative;
        cursor: default;
      }
      .clock-card:hover {
        border-color: var(--border-strong);
        box-shadow: var(--shadow-md);
        transform: translateY(-1px);
      }

      .card-header {
        display: flex;
        align-items: center;
        gap: 12px;
        margin-bottom: 16px;
      }
      .country-flag {
        font-size: 1.75rem;
        line-height: 1;
        flex-shrink: 0;
      }
      .country-info { flex: 1; min-width: 0; }
      .country-name {
        font-size: 0.9375rem;
        font-weight: 600;
        color: var(--text-primary);
        display: flex;
        align-items: center;
        gap: 8px;
        margin-bottom: 2px;
        letter-spacing: -0.01em;
      }
      .timezone-info {
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        color: var(--text-muted);
        font-weight: 500;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .delete-btn {
        opacity: 0;
        width: 24px;
        height: 24px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        background: transparent;
        border: 1px solid transparent;
        border-radius: var(--radius-sm);
        color: var(--text-muted);
        cursor: pointer;
        transition: all var(--transition);
        font-size: 0.75rem;
        flex-shrink: 0;
      }
      .clock-card:hover .delete-btn { opacity: 1; }
      .delete-btn:hover {
        background: var(--status-off-bg);
        color: var(--status-off);
      }
      .delete-btn:focus-visible {
        opacity: 1;
        outline: 2px solid var(--accent);
        outline-offset: 2px;
      }

      .time-section {
        padding: 16px 0;
        border-top: 1px solid var(--border);
        border-bottom: 1px solid var(--border);
        margin-bottom: 12px;
      }
      .time-display {
        font-family: var(--font-mono);
        font-size: 2rem;
        font-weight: 600;
        color: var(--text-primary);
        letter-spacing: -0.04em;
        line-height: 1.1;
        margin-bottom: 6px;
        font-variant-numeric: tabular-nums;
      }
      .date-display {
        font-size: 0.8125rem;
        color: var(--text-secondary);
        font-weight: 500;
      }

      .status-section {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }
      .status-indicator {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 4px 10px;
        font-size: 0.75rem;
        font-weight: 500;
        border-radius: 999px;
        border: 1px solid transparent;
        transition: all var(--transition);
      }
      .status-indicator::before {
        content: '';
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: currentColor;
        flex-shrink: 0;
      }
      .working-hours {
        background: var(--status-working-bg);
        color: var(--status-working);
      }
      .off-hours {
        background: var(--status-off-bg);
        color: var(--status-off);
      }
      .current-timezone {
        background: var(--status-current-bg);
        color: var(--status-current);
      }
      .time-diff {
        font-family: var(--font-mono);
        font-size: 0.75rem;
        color: var(--text-muted);
        font-weight: 500;
      }

      /* ============================================================
         Footer
         ============================================================ */
      .footer {
        text-align: center;
        padding: 20px 0;
        font-size: 0.8125rem;
        color: var(--text-muted);
      }

      /* ============================================================
         Floating control buttons (fullscreen / refresh / add tz)
         ============================================================ */
      .controls {
        position: fixed;
        bottom: 24px;
        right: 24px;
        display: flex;
        flex-direction: column;
        gap: 8px;
        z-index: 50;
      }
      .control-btn {
        width: 40px;
        height: 40px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        background: var(--bg-elevated);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        color: var(--text-secondary);
        cursor: pointer;
        box-shadow: var(--shadow-sm);
        transition: all var(--transition);
        font-size: 0.875rem;
      }
      .control-btn:hover {
        background: var(--bg-subtle);
        color: var(--text-primary);
        border-color: var(--border-strong);
        box-shadow: var(--shadow-md);
      }
      .control-btn:focus-visible {
        outline: 2px solid var(--accent);
        outline-offset: 2px;
      }
      .control-btn:active { transform: scale(0.96); }

      /* ============================================================
         Notification
         ============================================================ */
      .notification {
        position: fixed;
        top: 24px;
        right: 24px;
        padding: 12px 16px;
        background: var(--bg-elevated);
        border: 1px solid var(--border);
        border-left: 3px solid var(--accent);
        border-radius: var(--radius-md);
        color: var(--text-primary);
        font-size: 0.875rem;
        font-weight: 500;
        box-shadow: var(--shadow-lg);
        z-index: 100;
        transform: translateX(120%);
        transition: transform 200ms cubic-bezier(0.16, 1, 0.3, 1);
        max-width: 360px;
      }
      .notification.show { transform: translateX(0); }
      .notification.error { border-left-color: var(--status-off); }
      .notification.success { border-left-color: var(--status-working); }

      /* ============================================================
         Scrollbar
         ============================================================ */
      ::-webkit-scrollbar { width: 10px; height: 10px; }
      ::-webkit-scrollbar-track { background: transparent; }
      ::-webkit-scrollbar-thumb {
        background: var(--border-strong);
        border-radius: 999px;
        border: 2px solid var(--bg);
      }
      ::-webkit-scrollbar-thumb:hover { background: var(--text-muted); }

      /* ============================================================
         Selection
         ============================================================ */
      ::selection { background: var(--focus-ring); color: var(--text-primary); }

      /* ============================================================
         Responsive
         ============================================================ */
      @media (max-width: 1024px) {
        .main-content { grid-template-columns: 1fr; }
      }
      @media (max-width: 640px) {
        body { padding: 20px 16px 80px; }
        .header h1 { font-size: 1.375rem; }
        .stats-bar { grid-template-columns: repeat(2, 1fr); }
        .stat-number { font-size: 1.25rem; }
        .time-display { font-size: 1.75rem; }
        .clock-card, .card { padding: 18px; }
        .theme-toggle span { display: none; }
      }

      /* ============================================================
         WorldTimeBuddy-style 24h strip + team coverage + best-time
         — appended below the original layout, shares all design tokens.
         ============================================================ */
      .wtb-section {
        display: flex;
        flex-direction: column;
        gap: 24px;
      }
      .wtb-section-title {
        display: flex;
        align-items: center;
        gap: 10px;
        font-size: 1.0625rem;
        font-weight: 600;
        color: var(--text-primary);
        letter-spacing: -0.01em;
      }
      .wtb-section-title i { color: var(--text-muted); font-size: 0.9375rem; }
      .wtb-section-sub {
        font-size: 0.8125rem;
        color: var(--text-secondary);
        margin-top: -12px;
        margin-bottom: 4px;
        line-height: 1.55;
      }

      /* ---- 24h horizontal bar (one row per timezone) ---- */
      .wtb-grid {
        display: grid;
        grid-template-columns: 180px 1fr;
        gap: 12px;
        align-items: stretch;
      }
      .wtb-grid-header-row {
        display: contents;
      }
      .wtb-row {
        display: contents;
      }
      .wtb-label {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 8px 0;
        font-size: 0.8125rem;
        font-weight: 500;
        color: var(--text-primary);
      }
      .wtb-label-flag {
        font-size: 1.125rem;
        line-height: 1;
      }
      .wtb-label-name { flex: 1; min-width: 0; }
      .wtb-label-offset {
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        color: var(--text-muted);
        font-weight: 500;
      }

      .wtb-track {
        position: relative;
        height: 36px;
        background: var(--bg-subtle);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        /* overflow visible so the NOW cursor's knob sticks out above
           and the inner segments still get visually clipped by border-radius */
      }
      .wtb-hour-ticks {
        position: absolute;
        inset: 0;
        display: grid;
        grid-template-columns: repeat(24, 1fr);
        pointer-events: none;
      }
      .wtb-hour-tick {
        border-right: 1px solid var(--border);
        opacity: 0.5;
      }
      .wtb-hour-tick:last-child { border-right: none; }

      /* Working-hours segment */
      .wtb-segment {
        position: absolute;
        top: 6px;
        bottom: 6px;
        background: var(--status-working-bg);
        border-top: 1px solid var(--status-working);
        border-bottom: 1px solid var(--status-working);
        border-radius: 3px;
      }
      .wtb-segment::after {
        content: '';
        position: absolute;
        left: 0; right: 0;
        top: -1px; bottom: -1px;
        background: repeating-linear-gradient(
          45deg,
          transparent 0,
          transparent 4px,
          rgba(22, 163, 74, 0.08) 4px,
          rgba(22, 163, 74, 0.08) 8px
        );
        border-radius: 3px;
        pointer-events: none;
      }

      /* Off-hours crosshatch overlay */
      .wtb-off {
        position: absolute;
        top: 6px;
        bottom: 6px;
        background: repeating-linear-gradient(
          45deg,
          var(--bg-elevated) 0,
          var(--bg-elevated) 4px,
          var(--bg-subtle) 4px,
          var(--bg-subtle) 8px
        );
        border-top: 1px solid var(--border);
        border-bottom: 1px solid var(--border);
        border-radius: 3px;
        opacity: 0.85;
      }

      /* "Now" cursor on the track — center-aligned so the line lands
         exactly on its corresponding axis tick. The label shows the
         current local time of this specific zone in HH:MM (24h). */
      .wtb-now-cursor {
        position: absolute;
        top: -3px;
        bottom: -3px;
        width: 2px;
        background: var(--accent);
        z-index: 3;
        pointer-events: none;
        transform: translateX(-1px);
      }
      .wtb-now-cursor-label {
        position: absolute;
        top: -22px;
        left: 50%;
        transform: translateX(-50%);
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        font-weight: 600;
        color: var(--accent-text);
        background: var(--accent);
        padding: 2px 6px;
        border-radius: 4px;
        white-space: nowrap;
        letter-spacing: 0.02em;
      }

      .wtb-axis {
        grid-column: 2 / 3;
        margin-top: 6px;
        position: relative;
        height: 14px;
      }
      .wtb-axis-tick {
        position: absolute;
        top: 0;
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        color: var(--text-muted);
        font-weight: 500;
        /* label anchored at left:X% with -50% shift so its visual center
           sits exactly at the corresponding hour position */
        transform: translateX(-50%);
        white-space: nowrap;
        line-height: 1;
      }
      .wtb-axis-tick.major { font-weight: 600; color: var(--text-secondary); }

      /* ---- Team coverage (overlap) row ---- */
      .wtb-coverage {
        position: relative;
        height: 44px;
        background: var(--bg-subtle);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        overflow: hidden;
        margin-top: 4px;
      }
      .wtb-coverage-bar {
        position: absolute;
        top: 0;
        bottom: 0;
        background: var(--status-working-bg);
        border-top: 2px solid var(--status-working);
        border-bottom: 2px solid var(--status-working);
      }
      .wtb-coverage-bar.partial {
        background: var(--status-current-bg);
        border-top-color: var(--status-current);
        border-bottom-color: var(--status-current);
      }
      .wtb-coverage-count {
        position: absolute;
        top: 50%;
        transform: translateY(-50%);
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--text-primary);
        padding: 0 6px;
      }
      .wtb-coverage-legend {
        display: flex;
        gap: 16px;
        flex-wrap: wrap;
        margin-top: 8px;
        font-size: 0.75rem;
        color: var(--text-secondary);
      }
      .wtb-coverage-legend-item {
        display: inline-flex;
        align-items: center;
        gap: 6px;
      }
      .wtb-coverage-swatch {
        width: 12px;
        height: 12px;
        border-radius: 3px;
        border: 1px solid transparent;
      }
      .wtb-coverage-swatch.full {
        background: var(--status-working-bg);
        border-color: var(--status-working);
      }
      .wtb-coverage-swatch.partial {
        background: var(--status-current-bg);
        border-color: var(--status-current);
      }

      /* ---- Best meeting times ---- */
      .wtb-meetings {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 12px;
      }
      .wtb-meeting-card {
        background: var(--bg-elevated);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        padding: 14px 16px;
        transition: all var(--transition);
        position: relative;
      }
      .wtb-meeting-card:hover {
        border-color: var(--border-strong);
        box-shadow: var(--shadow-md);
        transform: translateY(-1px);
      }
      .wtb-meeting-quality {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-size: 0.6875rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        padding: 3px 8px;
        border-radius: 999px;
        margin-bottom: 10px;
      }
      .wtb-meeting-quality.excellent {
        background: var(--status-working-bg);
        color: var(--status-working);
      }
      .wtb-meeting-quality.good {
        background: var(--status-current-bg);
        color: var(--status-current);
      }
      .wtb-meeting-quality.weak {
        background: var(--bg-subtle);
        color: var(--text-muted);
      }
      .wtb-meeting-quality::before {
        content: '';
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: currentColor;
      }
      .wtb-meeting-time {
        font-family: var(--font-mono);
        font-size: 1.25rem;
        font-weight: 600;
        color: var(--text-primary);
        letter-spacing: -0.02em;
        margin-bottom: 4px;
        font-variant-numeric: tabular-nums;
      }
      .wtb-meeting-zones {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        margin-top: 8px;
      }
      .wtb-meeting-zone-chip {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        font-weight: 500;
        padding: 3px 8px;
        background: var(--bg-subtle);
        border: 1px solid var(--border);
        border-radius: 999px;
        color: var(--text-secondary);
      }

      /* ---- Responsive adjustments for WTB section ---- */
      @media (max-width: 1024px) {
        .wtb-grid { grid-template-columns: 130px 1fr; }
        .wtb-axis-tick { font-size: 0.5625rem; }
      }
      @media (max-width: 640px) {
        .wtb-grid {
          grid-template-columns: 1fr;
          gap: 4px;
        }
        .wtb-label {
          padding: 6px 0 2px;
        }
        .wtb-axis { display: none; }
        .wtb-meetings { grid-template-columns: 1fr; }
      }

      /* ============================================================
         Hour Explorer — WorldTimeBuddy-style hover/drag line
         Shows per-zone local time corresponding to a movable cursor
         on a shared 24h UTC strip.
         ============================================================ */
      .hex-section-title {
        display: flex;
        align-items: center;
        gap: 10px;
        font-size: 1.0625rem;
        font-weight: 600;
        color: var(--text-primary);
        letter-spacing: -0.01em;
        margin-bottom: 4px;
      }
      .hex-section-title i { color: var(--text-muted); font-size: 0.9375rem; }

      .hex-strip-wrap {
        position: relative;
        user-select: none;
        -webkit-user-select: none;
        cursor: crosshair;
      }
      .hex-strip {
        position: relative;
        height: 48px;
        background: var(--bg-subtle);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        /* overflow visible so the cursor knob sticks out above and
           inner content is clipped by border-radius anyway */
      }
      .hex-strip-ticks {
        position: absolute;
        inset: 0;
        display: grid;
        grid-template-columns: repeat(24, 1fr);
        pointer-events: none;
      }
      .hex-strip-tick {
        border-right: 1px solid var(--border);
        opacity: 0.5;
      }
      .hex-strip-tick:last-child { border-right: none; }
      .hex-strip-tick.major {
        opacity: 0.85;
        border-right-color: var(--border-strong);
      }
      .hex-strip-axis {
        margin-top: 4px;
        position: relative;
        height: 14px;
      }
      .hex-strip-axis-tick {
        position: absolute;
        top: 0;
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        color: var(--text-muted);
        font-weight: 500;
        transform: translateX(-50%);
        white-space: nowrap;
        line-height: 1;
      }
      .hex-strip-axis-tick.major { font-weight: 600; color: var(--text-secondary); }

      /* The draggable hover-line — accent-cursor following mouse.
         The vertical line is center-aligned on its anchor X coord so
         it sits exactly over the corresponding axis tick. The label
         shows the current reference time in HH:MM CST. */
      .hex-cursor {
        position: absolute;
        top: 0;
        bottom: 0;
        width: 2px;
        margin-left: -1px;
        pointer-events: none;
        z-index: 5;
      }
      .hex-cursor::before {
        content: '';
        position: absolute;
        left: 0;
        top: 0; bottom: 0;
        width: 2px;
        background: var(--accent);
      }
      .hex-cursor-label {
        position: absolute;
        top: -22px;
        left: 50%;
        transform: translateX(-50%);
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        font-weight: 600;
        color: var(--accent-text);
        background: var(--accent);
        padding: 2px 8px;
        border-radius: 4px;
        white-space: nowrap;
        letter-spacing: 0.04em;
      }

      /* Per-zone rows table */
      .hex-rows {
        margin-top: 20px;
        display: grid;
        grid-template-columns: 180px 1fr;
        gap: 12px;
        align-items: stretch;
      }
      .hex-row-label {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 8px 0;
        font-size: 0.8125rem;
        font-weight: 500;
        color: var(--text-primary);
      }
      .hex-row-flag { font-size: 1.125rem; line-height: 1; }
      .hex-row-name { flex: 1; min-width: 0; }
      .hex-row-offset {
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        color: var(--text-muted);
        font-weight: 500;
      }
      .hex-row-time {
        display: flex;
        flex-direction: column;
        gap: 2px;
        padding: 8px 12px;
        background: var(--bg-elevated);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        transition: all var(--transition);
      }
      .hex-row-time.live {
        background: var(--bg-subtle);
        border-color: var(--border-strong);
      }
      .hex-row-clock {
        font-family: var(--font-mono);
        font-size: 1.125rem;
        font-weight: 600;
        color: var(--text-primary);
        letter-spacing: -0.02em;
        font-variant-numeric: tabular-nums;
        line-height: 1.1;
      }
      .hex-row-clock .meridiem {
        font-family: var(--font-mono);
        font-size: 0.75rem;
        color: var(--text-muted);
        font-weight: 500;
        margin-left: 4px;
      }
      .hex-row-date {
        font-size: 0.75rem;
        color: var(--text-secondary);
        font-weight: 500;
      }
      .hex-row-status {
        font-size: 0.6875rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        padding: 2px 8px;
        border-radius: 999px;
        display: inline-block;
        width: fit-content;
        margin-top: 2px;
      }
      .hex-row-status.working {
        background: var(--status-working-bg);
        color: var(--status-working);
      }
      .hex-row-status.off {
        background: var(--status-off-bg);
        color: var(--status-off);
      }
      .hex-row-status.current {
        background: var(--status-current-bg);
        color: var(--status-current);
      }

      .hex-meta {
        margin-top: 16px;
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        padding: 10px 14px;
        background: var(--bg-subtle);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        font-size: 0.8125rem;
        color: var(--text-secondary);
      }
      .hex-meta-utc {
        font-family: var(--font-mono);
        font-size: 0.9375rem;
        font-weight: 600;
        color: var(--text-primary);
        font-variant-numeric: tabular-nums;
      }
      .hex-meta-buttons { display: inline-flex; gap: 6px; }
      .hex-btn {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 6px 12px;
        background: var(--bg-elevated);
        border: 1px solid var(--border);
        border-radius: var(--radius-md);
        color: var(--text-primary);
        font-family: inherit;
        font-size: 0.75rem;
        font-weight: 500;
        cursor: pointer;
        transition: all var(--transition);
      }
      .hex-btn:hover {
        background: var(--bg-subtle);
        border-color: var(--border-strong);
      }
      .hex-btn:focus-visible {
        outline: 2px solid var(--accent);
        outline-offset: 2px;
      }
      .hex-btn.primary {
        background: var(--accent);
        color: var(--accent-text);
        border-color: var(--accent);
      }
      .hex-btn.primary:hover {
        background: var(--accent-hover);
        border-color: var(--accent-hover);
      }
      .hex-btn i { font-size: 0.6875rem; }

      @media (max-width: 1024px) {
        .hex-rows { grid-template-columns: 130px 1fr; }
      }
      @media (max-width: 640px) {
        .hex-rows { grid-template-columns: 1fr; gap: 4px; }
        .hex-row-label { padding: 6px 0 2px; }
        .hex-strip-axis-tick { font-size: 0.5625rem; }
      }
    </style>
  </head>
  <body>
    <a class="skip-link" href="#main">Skip to main content</a>

    <div class="page">
      <header class="header">
        <div class="header-titles">
          <h1>Team Time Zone Clock</h1>
          <p>Real-time global team sync · collaborate more efficiently</p>
        </div>
        <button class="theme-toggle" onclick="toggleTheme()" aria-label="Toggle theme">
          <i class="fas fa-moon"></i>
          <span>Dark mode</span>
        </button>
      </header>

      <div class="search-container" role="search">
        <i class="fas fa-search" aria-hidden="true"></i>
        <input
          type="text"
          class="search-box"
          id="searchBox"
          placeholder="Search timezone or country…"
          onkeyup="filterClocks()"
          aria-label="Search timezone or country"
        >
      </div>

      <div class="stats-bar" id="statsBar" aria-live="polite">
        <!-- Stats rendered by JS -->
      </div>

      <main class="main-content" id="main">
        <section class="left-column" aria-label="Sidebar tools">
          <!-- Calendar -->
          <div class="card calendar-container">
            <div class="calendar-header">
              <button class="nav-btn" onclick="previousMonth()" aria-label="Previous month">
                <i class="fas fa-chevron-left"></i>
              </button>
              <div class="calendar-title-block">
                <h3 id="calendarMonth"></h3>
                <p id="calendarYear"></p>
              </div>
              <button class="nav-btn" onclick="nextMonth()" aria-label="Next month">
                <i class="fas fa-chevron-right"></i>
              </button>
            </div>
            <div class="calendar-grid">
              <div class="weekdays" aria-hidden="true">
                <div class="weekday">Sun</div>
                <div class="weekday">Mon</div>
                <div class="weekday">Tue</div>
                <div class="weekday">Wed</div>
                <div class="weekday">Thu</div>
                <div class="weekday">Fri</div>
                <div class="weekday">Sat</div>
              </div>
              <div class="days-grid" id="daysGrid">
                <!-- Days rendered by JS -->
              </div>
            </div>
            <div class="calendar-footer">
              <span class="today-label">Today</span>
              <span class="today-date" id="todayDate"></span>
            </div>
          </div>

          <!-- Time zone converter -->
          <div class="card">
            <div class="card-title">
              <i class="fas fa-exchange-alt" aria-hidden="true"></i>
              <span>Time zone converter</span>
            </div>
            <div class="converter-form">
              <input
                type="datetime-local"
                class="converter-input"
                id="converterTime"
                aria-label="Select time"
              >
              <select class="converter-input" id="converterFrom" aria-label="From timezone">
                <!-- Options rendered by JS -->
              </select>
              <select class="converter-input" id="converterTo" aria-label="To timezone">
                <!-- Options rendered by JS -->
              </select>
              <button class="submit-btn" onclick="convertTime()">
                <i class="fas fa-sync-alt" aria-hidden="true"></i>
                Convert time
              </button>
              <div class="converter-result" id="converterResult" aria-live="polite">
                Select a time and timezone to convert
              </div>
            </div>
          </div>
        </section>

        <section class="right-column" aria-label="Team timezones">
          <div class="clock-container" id="clockContainer">
            <!-- Clock cards rendered by JS -->
          </div>
        </section>
      </main>

      <!-- =======================================================
           WorldTimeBuddy-style team-availability planner
           (appended below the original two-column layout;
           reuses every design token — same dark/light theme)
           ======================================================= -->
      <section class="wtb-section" aria-label="Team coordination strips">
        <div style="display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap;">
          <h2 class="wtb-section-title" style="margin-bottom: 0;">
            <i class="fas fa-clock" aria-hidden="true"></i>
            Team time strips
          </h2>
          <button class="hex-btn primary" id="wtbNowBtn" title="Snap cursor back to the current moment">
            <i class="fas fa-circle" style="font-size:0.5rem;"></i>
            Now
          </button>
        </div>
        <p class="wtb-section-sub">
          The horizontal 24-hour bars instantly show each zone's work / rest pattern.
          Drag the dark line on any track to explore a different moment; each label
          shows that zone's local time (24h). Green = working, hatch = off-hours.
        </p>

        <div class="card">
          <div class="wtb-grid" id="wtbGrid">
            <!-- 24h tracks rendered by JS -->
          </div>
          <div class="wtb-axis" id="wtbAxis" aria-hidden="true"></div>
        </div>

        <!-- ===========================================================
             Hour Explorer — WTB-style hover/drag selector
             A draggable reference line on the 24h UTC strip; below
             it the table shows each zone's local time at that point.
             =========================================================== -->
        <div class="card">
          <h3 class="hex-section-title">
            <i class="fas fa-location-crosshairs" aria-hidden="true"></i>
            Hour Explorer
          </h3>
          <p class="wtb-section-sub">
            Drag the dark line to any CST (China) time and each zone below updates
            in sync with the local 24-hour clock. Click "Now" to jump back to the current China time.
          </p>
          <div class="hex-strip-wrap" id="hexStripWrap" aria-label="Time selector strip">
            <div class="hex-strip" id="hexStrip">
              <div class="hex-strip-ticks" id="hexStripTicks"></div>
              <div class="hex-cursor" id="hexCursor" style="display:none;">
                <span class="hex-cursor-label" id="hexCursorLabel">00:00</span>
              </div>
            </div>
            <div class="hex-strip-axis" id="hexStripAxis" aria-hidden="true"></div>
          </div>

          <div class="hex-rows" id="hexRows" aria-live="polite">
            <!-- per-zone rows rendered by JS -->
          </div>

          <div class="hex-meta">
            <div>
              <div style="font-size: 0.6875rem; font-weight: 600; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.06em; margin-bottom: 2px;">
                Current reference time (CST · China)
              </div>
              <span class="hex-meta-utc" id="hexMetaUtc">--:--</span>
              <span id="hexMetaDate" style="margin-left: 8px; color: var(--text-secondary); font-size: 0.8125rem;"></span>
            </div>
            <div class="hex-meta-buttons">
              <button class="hex-btn" id="hexShiftMinus" title="Back 1 hour">
                <i class="fas fa-chevron-left"></i>
                -1h
              </button>
              <button class="hex-btn primary" id="hexNow" title="Back to current time">
                <i class="fas fa-circle" style="font-size:0.5rem;"></i>
                Now
              </button>
              <button class="hex-btn" id="hexShiftPlus" title="Forward 1 hour">
                +1h
                <i class="fas fa-chevron-right"></i>
              </button>
            </div>
          </div>
        </div>

        <div class="card">
          <div class="card-title">
            <i class="fas fa-users" aria-hidden="true"></i>
            <span>Team coverage heatmap</span>
          </div>
          <p class="wtb-section-sub" style="margin: -10px 0 12px;">
            How many team members are online in the same hour?
            Dark green = everyone online, orange = partial only.
          </p>
          <div class="wtb-coverage" id="wtbCoverage" aria-label="Team coverage heatmap"></div>
          <div class="wtb-coverage-legend">
            <span class="wtb-coverage-legend-item">
              <span class="wtb-coverage-swatch full"></span>
              Everyone online
            </span>
            <span class="wtb-coverage-legend-item">
              <span class="wtb-coverage-swatch partial"></span>
              Partial
            </span>
          </div>
        </div>

        <div class="card">
          <div class="card-title">
            <i class="fas fa-handshake" aria-hidden="true"></i>
            <span>Recommended meeting times</span>
          </div>
          <p class="wtb-section-sub" style="margin: -10px 0 12px;">
            Based on working-hour overlap, ranked by coverage,
            showing UTC time + each zone's local time.
          </p>
          <div class="wtb-meetings" id="wtbMeetings"></div>
        </div>
      </section>

      <footer class="footer">
        <p>Auto-refresh every second · real-time global sync</p>
      </footer>
    </div>

    <div class="controls" role="toolbar" aria-label="Quick actions">
      <button class="control-btn" onclick="toggleFullscreen()" title="Fullscreen (F)" aria-label="Fullscreen">
        <i class="fas fa-expand" aria-hidden="true"></i>
      </button>
      <button class="control-btn" onclick="updateAllClocks()" title="Manual refresh (R)" aria-label="Manual refresh">
        <i class="fas fa-sync-alt" aria-hidden="true"></i>
      </button>
      <button class="control-btn" onclick="addCustomTimezone()" title="Add timezone (+)" aria-label="Add timezone">
        <i class="fas fa-plus" aria-hidden="true"></i>
      </button>
    </div>

    <script>
      // ============================================================
      // Timezone data — single source of truth
      // ============================================================
      const timezones = [
        { name: "China",        flag: "🇨🇳", timezone: "Asia/Shanghai",      workingHours: [9, 18] },
        { name: "India",        flag: "🇮🇳", timezone: "Asia/Kolkata",       workingHours: [9, 18] },
        { name: "UK",        flag: "🇬🇧", timezone: "Europe/London",      workingHours: [9, 17] },
        { name: "UTC",        flag: "🌐",  timezone: "UTC",                workingHours: [9, 18] },
        { name: "US West Coast",  flag: "🇺🇸", timezone: "America/Los_Angeles", workingHours: [9, 18] },
        { name: "Current location",    flag: "📍",  timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, workingHours: [9, 18], isCurrent: true },
      ];

      let currentCalendarDate = new Date();
      let selectedDate = null;

      const monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
      ];

      // ============================================================
      // Status helpers
      // ============================================================
      function getWorkingStatus(hour, workingHours, isCurrent = false) {
        if (isCurrent) return "current-timezone";
        return hour >= workingHours[0] && hour < workingHours[1] ? "working-hours" : "off-hours";
      }

      function getStatusText(hour, workingHours, isCurrent = false) {
        if (isCurrent) return "Current zone";
        return hour >= workingHours[0] && hour < workingHours[1] ? "Working hours" : "Off hours";
      }

      function formatTime(date) {
        return date.toLocaleTimeString("en-GB", {
          hour12: false, hour: "2-digit", minute: "2-digit", second: "2-digit",
        });
      }

      function formatDate(date) {
        return date.toLocaleDateString("en-US", {
          year: "numeric", month: "long", day: "numeric", weekday: "long",
        });
      }

      // ============================================================
      // Clock cards
      // ============================================================
      function createClockCard(timezone) {
        const now = new Date();
        const localTime = new Date(now.toLocaleString("en-US", { timeZone: timezone.timezone }));
        const hour = localTime.getHours();

        const timeDiff = Math.round((localTime.getTime() - now.getTime()) / (1000 * 60 * 60));
        const timeDiffText = timeDiff === 0
          ? 'Local time'
          : timeDiff > 0
            ? `+${timeDiff} h`
            : `${timeDiff} h`;

        const statusClass = getWorkingStatus(hour, timezone.workingHours, timezone.isCurrent);
        const statusText = getStatusText(hour, timezone.workingHours, timezone.isCurrent);

        return `
          <article class="clock-card" data-timezone-name="${timezone.name.toLowerCase()}">
            <div class="card-header">
              <span class="country-flag" aria-hidden="true">${timezone.flag}</span>
              <div class="country-info">
                <div class="country-name">
                  ${timezone.name}
                  ${!timezone.isCurrent
                    ? `<button class="delete-btn" onclick="removeTimezone('${timezone.timezone}')" title="Delete timezone" aria-label="Delete timezone ${timezone.name}"><i class="fas fa-trash-alt" aria-hidden="true"></i></button>`
                    : ''}
                </div>
                <div class="timezone-info">${timezone.timezone}</div>
              </div>
            </div>

            <div class="time-section">
              <div class="time-display" data-timezone="${timezone.timezone}">${formatTime(localTime)}</div>
              <div class="date-display" data-timezone="${timezone.timezone}">${formatDate(localTime)}</div>
            </div>

            <div class="status-section">
              <span class="status-indicator ${statusClass}">${statusText}</span>
              <span class="time-diff">${timeDiffText}</span>
            </div>
          </article>
        `;
      }

      function createStatsBar() {
        const now = new Date();
        let workingCount = 0;
        let offCount = 0;

        timezones.forEach(tz => {
          if (tz.isCurrent) return;
          const localTime = new Date(now.toLocaleString("en-US", { timeZone: tz.timezone }));
          const hour = localTime.getHours();
          if (hour >= tz.workingHours[0] && hour < tz.workingHours[1]) workingCount++;
          else offCount++;
        });

        return `
          <div class="stat-item">
            <span class="stat-number">${timezones.length}</span>
            <span class="stat-label">Total zones</span>
          </div>
          <div class="stat-item">
            <span class="stat-number">${workingCount}</span>
            <span class="stat-label">Working hours</span>
          </div>
          <div class="stat-item">
            <span class="stat-number">${offCount}</span>
            <span class="stat-label">Off hours</span>
          </div>
          <div class="stat-item">
            <span class="stat-number">${formatTime(now)}</span>
            <span class="stat-label">Local time</span>
          </div>
        `;
      }

      function updateAllClocks() {
        document.getElementById("clockContainer").innerHTML = timezones.map(createClockCard).join("");
        document.getElementById("statsBar").innerHTML = createStatsBar();
        updateTimezoneOptions();
      }

      function updateTimes() {
        timezones.forEach((timezone) => {
          const now = new Date();
          const localTime = new Date(now.toLocaleString("en-US", { timeZone: timezone.timezone }));
          const hour = localTime.getHours();

          const timeElements = document.querySelectorAll(`[data-timezone="${timezone.timezone}"]`);
          timeElements.forEach((element) => {
            if (element.classList.contains("time-display")) {
              element.textContent = formatTime(localTime);
            } else if (element.classList.contains("date-display")) {
              element.textContent = formatDate(localTime);
            }
          });

          const card = timeElements[0]?.closest(".clock-card");
          if (card) {
            const statusElement = card.querySelector(".status-indicator");
            statusElement.className = `status-indicator ${getWorkingStatus(hour, timezone.workingHours, timezone.isCurrent)}`;
            statusElement.textContent = getStatusText(hour, timezone.workingHours, timezone.isCurrent);
          }
        });

        document.getElementById("statsBar").innerHTML = createStatsBar();
      }

      // ============================================================
      // Theme
      // ============================================================
      function toggleTheme() {
        const body = document.body;
        const themeBtn = document.querySelector('.theme-toggle');
        const icon = themeBtn.querySelector('i');
        const text = themeBtn.querySelector('span');

        body.classList.toggle('dark-mode');

        if (body.classList.contains('dark-mode')) {
          icon.className = 'fas fa-sun';
          text.textContent = 'Light mode';
        } else {
          icon.className = 'fas fa-moon';
          text.textContent = 'Dark mode';
        }

        localStorage.setItem('theme', body.classList.contains('dark-mode') ? 'dark' : 'light');
      }

      // ============================================================
      // Calendar
      // ============================================================
      function generateCalendar(date) {
        const year = date.getFullYear();
        const month = date.getMonth();
        const today = new Date();

        document.getElementById('calendarMonth').textContent = monthNames[month];
        document.getElementById('calendarYear').textContent = year;

        const firstDay = new Date(year, month, 1);
        const lastDay = new Date(year, month + 1, 0);
        const firstDayWeek = firstDay.getDay();
        const daysInMonth = lastDay.getDate();
        const prevMonth = new Date(year, month, 0);
        const daysInPrevMonth = prevMonth.getDate();

        const daysGrid = document.getElementById('daysGrid');
        daysGrid.innerHTML = '';

        for (let i = firstDayWeek - 1; i >= 0; i--) {
          daysGrid.appendChild(createDayElement(daysInPrevMonth - i, true));
        }

        for (let day = 1; day <= daysInMonth; day++) {
          const dayElement = createDayElement(day, false);
          const currentDate = new Date(year, month, day);
          if (currentDate.toDateString() === today.toDateString()) dayElement.classList.add('today');
          if (selectedDate && currentDate.toDateString() === selectedDate.toDateString()) dayElement.classList.add('selected');
          daysGrid.appendChild(dayElement);
        }

        const totalCells = daysGrid.children.length;
        const remainingCells = 42 - totalCells;
        for (let day = 1; day <= remainingCells; day++) {
          daysGrid.appendChild(createDayElement(day, true));
        }

        updateTodayInfo();
      }

      function createDayElement(day, isOtherMonth) {
        const dayElement = document.createElement('div');
        dayElement.className = 'day';
        dayElement.textContent = day;
        dayElement.setAttribute('role', 'button');
        dayElement.setAttribute('tabindex', '0');

        if (isOtherMonth) dayElement.classList.add('other-month');

        dayElement.addEventListener('click', function () {
          if (!isOtherMonth) {
            document.querySelectorAll('.day.selected').forEach(el => el.classList.remove('selected'));
            dayElement.classList.add('selected');
            selectedDate = new Date(currentCalendarDate.getFullYear(), currentCalendarDate.getMonth(), day);
            updateTodayInfo();
          }
        });

        dayElement.addEventListener('keydown', function (e) {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            dayElement.click();
          }
        });

        return dayElement;
      }

      function updateTodayInfo() {
        const today = new Date();
        const displayDate = selectedDate || today;
        const options = { year: 'numeric', month: 'long', day: 'numeric', weekday: 'long' };
        document.getElementById('todayDate').textContent = displayDate.toLocaleDateString('en-US', options);
      }

      function previousMonth() {
        currentCalendarDate.setMonth(currentCalendarDate.getMonth() - 1);
        generateCalendar(currentCalendarDate);
      }

      function nextMonth() {
        currentCalendarDate.setMonth(currentCalendarDate.getMonth() + 1);
        generateCalendar(currentCalendarDate);
      }

      // ============================================================
      // Search
      // ============================================================
      function filterClocks() {
        const searchTerm = document.getElementById('searchBox').value.toLowerCase();
        const cards = document.querySelectorAll('.clock-card');

        cards.forEach(card => {
          const name = card.getAttribute('data-timezone-name');
          card.style.display = name.includes(searchTerm) ? '' : 'none';
        });
      }

      // ============================================================
      // Add / remove timezones
      // ============================================================
      function addCustomTimezone() {
        const timezone = prompt("Enter timezone identifier (e.g. Asia/Tokyo):");
        if (!timezone) return;

        try {
          Intl.DateTimeFormat(undefined, { timeZone: timezone });
          const name = prompt("Enter timezone name:", timezone.split("/").pop());
          if (!name) return;

          timezones.push({ name, flag: "🌍", timezone, workingHours: [9, 18] });
          updateAllClocks();
          showNotification(`Timezone added: ${name}`, 'success');
        } catch (e) {
          showNotification("Invalid timezone identifier, please retry", 'error');
        }
      }

      function removeTimezone(timezoneId) {
        const index = timezones.findIndex(tz => tz.timezone === timezoneId);
        if (index === -1 || timezones[index].isCurrent) {
          showNotification("Cannot delete the current location timezone", 'error');
          return;
        }
        if (!confirm(`Delete ${timezones[index].name} ?`)) return;

        const removedName = timezones[index].name;
        timezones.splice(index, 1);
        updateAllClocks();
        showNotification(`Timezone removed: ${removedName}`, 'success');
      }

      // ============================================================
      // Converter
      // ============================================================
      function updateTimezoneOptions() {
        const fromSelect = document.getElementById('converterFrom');
        const toSelect = document.getElementById('converterTo');

        fromSelect.innerHTML = '';
        toSelect.innerHTML = '';

        timezones.forEach(tz => {
          const o1 = document.createElement('option');
          o1.value = tz.timezone;
          o1.textContent = `${tz.flag} ${tz.name} (${tz.timezone})`;
          fromSelect.appendChild(o1);

          const o2 = o1.cloneNode(true);
          toSelect.appendChild(o2);
        });

        if (timezones.length > 0) {
          fromSelect.value = timezones[0].timezone;
          toSelect.value = timezones[timezones.length - 1].timezone;
        }
      }

      function convertTime() {
        const timeInput = document.getElementById('converterTime').value;
        const fromTimezone = document.getElementById('converterFrom').value;
        const toTimezone = document.getElementById('converterTo').value;
        const resultElement = document.getElementById('converterResult');

        if (!timeInput) {
          resultElement.textContent = "Please select a time";
          return;
        }

        try {
          const date = new Date(timeInput);
          const formatter = new Intl.DateTimeFormat('en-US', {
            timeZone: toTimezone,
            year: 'numeric', month: '2-digit', day: '2-digit',
            hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
          });
          const convertedTime = formatter.format(date);
          const fromTz = timezones.find(tz => tz.timezone === fromTimezone);
          const toTz = timezones.find(tz => tz.timezone === toTimezone);

          resultElement.innerHTML = `
            <strong>Result</strong>
            <div class="converted-time">${convertedTime}</div>
            <div class="converted-route">${fromTz ? fromTz.flag + ' ' + fromTz.name : fromTimezone} → ${toTz ? toTz.flag + ' ' + toTz.name : toTimezone}</div>
          `;
        } catch (e) {
          resultElement.textContent = "Conversion failed, please check the input";
        }
      }

      // ============================================================
      // Fullscreen
      // ============================================================
      function toggleFullscreen() {
        if (!document.fullscreenElement) {
          document.documentElement.requestFullscreen().catch(err => console.log(`Fullscreen error: ${err.message}`));
        } else {
          document.exitFullscreen();
        }
      }

      // ============================================================
      // Notification (right-side slide-in, minimal)
      // ============================================================
      function showNotification(message, type = 'info') {
        const notification = document.createElement('div');
        notification.className = `notification ${type}`;
        notification.textContent = message;
        document.body.appendChild(notification);

        // Slide in
        requestAnimationFrame(() => notification.classList.add('show'));

        setTimeout(() => {
          notification.classList.remove('show');
          setTimeout(() => notification.remove(), 250);
        }, 2800);
      }

      // ============================================================
      // Keyboard shortcuts
      // ============================================================
      document.addEventListener('keydown', function (e) {
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT' || e.target.tagName === 'TEXTAREA') return;

        switch (e.key.toLowerCase()) {
          case 'f': e.preventDefault(); toggleFullscreen(); break;
          case 't': e.preventDefault(); toggleTheme(); break;
          case 'r': e.preventDefault(); updateAllClocks(); break;
          case 'arrowleft': e.preventDefault(); previousMonth(); break;
          case 'arrowright': e.preventDefault(); nextMonth(); break;
          case '+':
          case '=': e.preventDefault(); addCustomTimezone(); break;
        }
      });

      // ============================================================
      // Init + tickers
      // ============================================================
      document.addEventListener('DOMContentLoaded', function () {
        const savedTheme = localStorage.getItem('theme');
        if (savedTheme !== 'light') {
          document.body.classList.add('dark-mode');
          const themeBtn = document.querySelector('.theme-toggle');
          themeBtn.querySelector('i').className = 'fas fa-sun';
          themeBtn.querySelector('span').textContent = 'Light mode';
        }

        updateAllClocks();
        generateCalendar(currentCalendarDate);
        updateTimezoneOptions();

        const now = new Date();
        const formattedNow = now.toISOString().slice(0, 16);
        document.getElementById('converterTime').value = formattedNow;

        setTimeout(() => showNotification("Welcome to Team Time Zone Clock", 'success'), 800);
      });

      setInterval(updateTimes, 1000);

      setInterval(() => {
        // Refresh clock cards once a minute (less DOM churn than every second
        // for stats / labels), and rebuild full layout on visibility change
        // and on focus.
        const now = new Date();
        document.getElementById('statsBar').innerHTML = createStatsBar();
      }, 60000);

      setInterval(() => {
        if (new Date().getHours() === 0 && new Date().getMinutes() === 0) {
          generateCalendar(currentCalendarDate);
        }
      }, 60000);

      document.addEventListener('visibilitychange', () => { if (!document.hidden) updateAllClocks(); });
      window.addEventListener('focus', updateAllClocks);
    </script>

    <!-- ============================================================
         WorldTimeBuddy-style team availability module
         (reads the same `timezones` array defined above)
         ============================================================ -->
    <script>
      (function () {
        'use strict';

        if (typeof timezones === 'undefined') {
          console.warn('wtb module: `timezones` array not found, aborting');
          return;
        }

        const gridEl = document.getElementById('wtbGrid');
        const axisEl = document.getElementById('wtbAxis');
        const coverageEl = document.getElementById('wtbCoverage');
        const meetingsEl = document.getElementById('wtbMeetings');
        if (!gridEl || !coverageEl || !meetingsEl) return;

        // ---------- Helpers ----------
        function getHourInZone(hourUtc, tzName) {
          const probe = new Date(Date.UTC(2000, 0, 1, hourUtc, 0, 0));
          return parseInt(
            new Intl.DateTimeFormat('en-US', {
              hour: '2-digit', hour12: false, timeZone: tzName,
            }).format(probe),
            10
          ) % 24;
        }

        // Format a UTC hour as a "HH:00" string in the given zone
        function formatHourInZone(utcHour, tzName) {
          const probe = new Date(Date.UTC(2000, 0, 1, utcHour, 0, 0));
          return new Intl.DateTimeFormat('en-GB', {
            hour: '2-digit', minute: '2-digit', hour12: false, timeZone: tzName,
          }).format(probe);
        }

        function utcOffsetLabel(tzName) {
          const probe = new Date(Date.UTC(2000, 0, 1, 0, 0, 0));
          const fmt = new Intl.DateTimeFormat('en-US', {
            timeZone: tzName, timeZoneName: 'shortOffset', hour: '2-digit',
          });
          const parts = fmt.formatToParts(probe);
          const off = parts.find(p => p.type === 'timeZoneName');
          return off ? off.value : '';
        }

        // Get the timezone offset in hours (e.g. +5.5 for Kolkata, -8 for LA).
        // Uses longOffset to parse "+hh:mm" precisely so half-hour zones work.
        function getZoneOffsetHours(tzName) {
          const probe = new Date(Date.UTC(2000, 0, 1, 0, 0, 0));
          const fmt = new Intl.DateTimeFormat('en-US', {
            timeZone: tzName, timeZoneName: 'longOffset', hour: '2-digit',
          });
          const parts = fmt.formatToParts(probe);
          const off = parts.find(p => p.type === 'timeZoneName');
          if (!off) return 0;
          // Matches "GMT+05:30", "GMT+8", "GMT-08:00", "UTC" etc.
          const m = off.value.match(/([+\-])(\d{1,2})(?::(\d{2}))?/);
          if (!m) return 0;
          const sign = m[1] === '+' ? 1 : -1;
          const h = parseInt(m[2], 10);
          const min = parseInt(m[3] || '0', 10);
          return sign * (h + min / 60);
        }

        // Convert a local [wStart, wEnd] working-hours window into UTC
        // coordinate segments. Returns 0..2 segments because working hours
        // can straddle midnight in UTC (e.g. US west coast 9-18 local =
        // 17-24 + 0-2 UTC). Each segment is {start, end} in [0, 24] UTC.
        function workingHoursToUtcSegments(wStart, wEnd, offsetHours) {
          // utc = local - offset (because if local is UTC+8 and it's noon
          // local, UTC is 04:00)
          let utcStart = wStart - offsetHours;
          let utcEnd = wEnd - offsetHours;
          const segs = [];
          if (utcStart >= 0 && utcEnd <= 24) {
            segs.push({ start: utcStart, end: utcEnd });
          } else if (utcStart < 0 && utcEnd <= 24) {
            // wraps backward across midnight
            segs.push({ start: utcStart + 24, end: 24 });
            if (utcEnd > 0) segs.push({ start: 0, end: utcEnd });
          } else if (utcStart >= 0 && utcEnd > 24) {
            // wraps forward across midnight
            segs.push({ start: utcStart, end: 24 });
            segs.push({ start: 0, end: utcEnd - 24 });
          } else {
            // both negative — try shifting by 24 in either direction
            // (only happens for extreme offsets like UTC-14)
            const s = ((utcStart % 24) + 24) % 24;
            const e = ((utcEnd % 24) + 24) % 24;
            if (s < e) segs.push({ start: s, end: e });
          }
          return segs.filter(s => s.end > s.start);
        }

        // ---------- Render the 24h strips ----------
        // The horizontal axis 0..24 represents the ANCHOR timezone's
        // hour-of-day (anchor = Asia/Shanghai, fixed UTC+8). Each zone's
        // local working hours are projected onto this axis so segments
        // align visually with the NOW cursor.
        const ANCHOR_TZ = 'Asia/Shanghai';

        function renderGrid() {
          const html = timezones.map(tz => {
            const wStart = tz.workingHours[0];
            const wEnd = tz.workingHours[1];
            // For segment placement we need the zone's offset **relative to
            // the anchor (CST)** — not its UTC offset — because the axis is
            // now in CST. deltaHours = zone offset - anchor offset.
            const zoneOffset = getZoneOffsetHours(tz.timezone);
            const anchorOffset = 8; // Asia/Shanghai = UTC+8 fixed
            const segOffset = zoneOffset - anchorOffset;
            const offsetLabel = utcOffsetLabel(tz.timezone);

            // Compute "where does [wStart, wEnd] in zone-local land on the
            // anchor-tz axis?". Reuses the same wrap-around math as the UTC
            // version by passing it the right offset.
            const segs = workingHoursToUtcSegments(wStart, wEnd, segOffset);

            const segmentsHtml = segs.map(s => {
              const leftPct = (s.start / 24) * 100;
              const widthPct = ((s.end - s.start) / 24) * 100;
              return `<div class="wtb-segment" style="left:${leftPct}%; width:${widthPct}%"></div>`;
            }).join('');

            return `
              <div class="wtb-label">
                <span class="wtb-label-flag">${tz.flag}</span>
                <span class="wtb-label-name">${tz.name}</span>
                <span class="wtb-label-offset" title="UTC ${zoneOffset >= 0 ? '+' : ''}${zoneOffset}">${offsetLabel}</span>
              </div>
              <div class="wtb-track" data-tz="${tz.timezone}" data-wstart="${wStart}" data-wend="${wEnd}" data-offset="${zoneOffset}">
                <div class="wtb-hour-ticks">
                  ${Array.from({ length: 24 }, () => '<div class="wtb-hour-tick"></div>').join('')}
                </div>
                <div class="wtb-off" style="left:0; right:0;"></div>
                ${segmentsHtml}
              </div>
            `;
          }).join('');
          gridEl.innerHTML = html;

          axisEl.innerHTML = Array.from({ length: 24 }, (_, i) => {
            const isMajor = i % 6 === 0;
            return `<span class="wtb-axis-tick${isMajor ? ' major' : ''}" style="left:${(i / 24) * 100}%">${String(i).padStart(2, '0')}</span>`;
          }).join('');
        }

        // ---------- Now cursor (draggable probe) ----------
        // The horizontal axis 0..24 of the WTB strip represents the
        // *anchor timezone's* hour-of-day (anchor = Asia/Shanghai, CST).
        // All 6 tracks share a single cursor position stored in
        // `wtbCursorCstFrac` (CST hour-of-day as decimal). The user can
        // drag any of the 6 cursors to explore a different moment; every
        // cursor (and its HH:MM label, showing the per-zone local time at
        // that moment) updates in sync.
        const ANCHOR_TZ_CURSOR = 'Asia/Shanghai';
        const ANCHOR_OFFSET_HOURS_CURSOR = 8;

        // Read the current CST hour-of-day as a decimal (e.g. 22.5 = 22:30)
        function currentCstFrac() {
          const now = new Date();
          const fmt = new Intl.DateTimeFormat('en-GB', {
            timeZone: ANCHOR_TZ_CURSOR,
            hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
          });
          const p = fmt.formatToParts(now);
          const hh = parseInt(p.find(x => x.type === 'hour').value, 10) % 24;
          const mm = parseInt(p.find(x => x.type === 'minute').value, 10);
          const ss = parseInt(p.find(x => x.type === 'second').value, 10);
          return hh + mm / 60 + ss / 3600;
        }

        // State: position of all 6 cursors on the 0..24 CST axis. Defaults
        // to "now" (current CST wall-clock). When the user drags, this is
        // updated to the dragged X position.
        let wtbCursorCstFrac = currentCstFrac();
        // True once the user has manually moved the cursor away from "now",
        // so we don't snap it back to real time on the next refresh tick.
        let wtbCursorUserMoved = false;

        // Translate `wtbCursorCstFrac` to a per-zone HH:MM (24h) label.
        // UTC instant equivalent to "today at CST hh:mm" = CST - 8h.
        function cstFracToZoneLabel(cstFrac, tzName) {
          const utcFrac = ((cstFrac - ANCHOR_OFFSET_HOURS_CURSOR) % 24 + 24) % 24;
          const probe = new Date(Date.UTC(2000, 0, 1, 0, 0, 0) + utcFrac * 3600 * 1000);
          return new Intl.DateTimeFormat('en-GB', {
            timeZone: tzName,
            hour: '2-digit', minute: '2-digit', hour12: false,
          }).format(probe);
        }

        function renderNowCursor() {
          // If the user hasn't manually moved the cursor, follow real time
          // so the labels always show the current moment until they engage.
          if (!wtbCursorUserMoved) {
            wtbCursorCstFrac = currentCstFrac();
          }
          const leftPct = (wtbCursorCstFrac / 24) * 100;
          document.querySelectorAll('.wtb-track').forEach(track => {
            track.querySelector('.wtb-now-cursor')?.remove();
            const cursor = document.createElement('div');
            cursor.className = 'wtb-now-cursor';
            cursor.style.left = `calc(${leftPct}% - 1px)`;
            // Per-zone local time as HH:MM (24h) at the cursor position
            const tz = track.getAttribute('data-tz');
            const label = document.createElement('div');
            label.className = 'wtb-now-cursor-label';
            label.textContent = cstFracToZoneLabel(wtbCursorCstFrac, tz);
            cursor.appendChild(label);
            track.appendChild(cursor);
          });
        }

        // ---------- Drag interaction (mirrors Hour Explorer's behavior) ----------
        // Event delegation: we listen on the grid container so that drag
        // listeners survive every re-render of the track elements. The
        // closest .wtb-track at the event target is the drag source.
        let wtbDragging = false;
        let wtbDragSource = null; // the .wtb-track where mousedown happened

        function setWtbCursorFromEvent(e) {
          if (!wtbDragSource) return;
          const rect = wtbDragSource.getBoundingClientRect();
          const x = Math.max(0, Math.min(rect.width,
            (e.clientX || (e.touches && e.touches[0].clientX)) - rect.left));
          // Snap to nearest minute
          const totalMinutes = Math.round((x / rect.width) * 24 * 60);
          wtbCursorCstFrac = totalMinutes / 60;
          wtbCursorUserMoved = true;
          renderNowCursor();
        }

        function findWtbTrack(target) {
          return target && target.closest && target.closest('.wtb-track');
        }

        // Mouse drag — bind once on the grid container
        if (gridEl) {
          gridEl.addEventListener('mousedown', (e) => {
            const track = findWtbTrack(e.target);
            if (!track) return;
            wtbDragging = true;
            wtbDragSource = track;
            setWtbCursorFromEvent(e);
          });
          gridEl.addEventListener('touchstart', (e) => {
            const track = findWtbTrack(e.target);
            if (!track) return;
            wtbDragging = true;
            wtbDragSource = track;
            setWtbCursorFromEvent(e);
          }, { passive: true });
          // Visual hint that the rows are draggable
          gridEl.style.cursor = 'ew-resize';
        }
        document.addEventListener('mousemove', (e) => {
          if (!wtbDragging) return;
          setWtbCursorFromEvent(e);
        });
        document.addEventListener('mouseup', () => {
          wtbDragging = false;
          wtbDragSource = null;
        });
        document.addEventListener('touchmove', (e) => {
          if (!wtbDragging) return;
          setWtbCursorFromEvent(e);
        }, { passive: true });
        document.addEventListener('touchend', () => {
          wtbDragging = false;
          wtbDragSource = null;
        });

        // "Now" button — re-anchor the cursor to the current real time
        const wtbNowBtn = document.getElementById('wtbNowBtn');
        if (wtbNowBtn) {
          wtbNowBtn.addEventListener('click', () => {
            wtbCursorUserMoved = false;
            wtbCursorCstFrac = currentCstFrac();
            renderNowCursor();
          });
        }

        // ---------- Team coverage ----------
        // Axis is in CST, so for each CST 0..23 hour, ask "in zone t this
        // moment, what's the local hour?" — that's
        //   utc = (cst - 8 + 24) % 24
        //   localHour(t, utc)
        // — and see if it falls inside [wStart, wEnd].
        function renderCoverage() {
          const coverage = new Array(24).fill(0);
          const total = timezones.length;
          const ANCHOR_OFFSET_HOURS = 8;
          timezones.forEach(tz => {
            const wStart = tz.workingHours[0];
            const wEnd = tz.workingHours[1];
            for (let cstH = 0; cstH < 24; cstH++) {
              const utcH = ((cstH - ANCHOR_OFFSET_HOURS) % 24 + 24) % 24;
              const localH = getHourInZone(utcH, tz.timezone);
              const inWork = wStart < wEnd
                ? (localH >= wStart && localH < wEnd)
                : (localH >= wStart || localH < wEnd); // wrap-around (e.g. night shift)
              if (inWork) coverage[cstH]++;
            }
          });

          // Merge contiguous runs at the same coverage level
          let bars = [];
          let runStart = 0;
          let runLevel = coverage[0];
          for (let h = 1; h < 24; h++) {
            if (coverage[h] === runLevel) continue;
            bars.push({ start: runStart, end: h, count: runLevel });
            runStart = h;
            runLevel = coverage[h];
          }
          bars.push({ start: runStart, end: 24, count: runLevel });

          coverageEl.innerHTML = bars.map(b => {
            const left = (b.start / 24) * 100;
            const width = ((b.end - b.start) / 24) * 100;
            const isPartial = b.count > 0 && b.count < total;
            const cssClass = isPartial ? ' partial' : '';
            const color = isPartial ? 'var(--text-primary)' : 'var(--status-working)';
            return `
              <div class="wtb-coverage-bar${cssClass}" style="left:${left}%; width:${width}%"></div>
              <span class="wtb-coverage-count" style="left:calc(${left}% + 6px); color:${color};">${b.count}/${total}</span>
            `;
          }).join('');
        }

        // ---------- Best meeting times ----------
        // Same shift trick as coverage: recommend CST hours, but the per-zone
        // "local time" is derived from that CST hour via UTC = CST - 8.
        function renderMeetings() {
          const slots = [];
          const ANCHOR_OFFSET_HOURS = 8;
          for (let cstH = 0; cstH < 24; cstH++) {
            const utcH = ((cstH - ANCHOR_OFFSET_HOURS) % 24 + 24) % 24;
            const richZones = [];
            timezones.forEach(tz => {
              const wStart = tz.workingHours[0];
              const wEnd = tz.workingHours[1];
              const localH = getHourInZone(utcH, tz.timezone);
              const inWork = wStart < wEnd
                ? (localH >= wStart && localH < wEnd)
                : (localH >= wStart || localH < wEnd);
              if (inWork) {
                richZones.push({ tz, localTime: formatHourInZone(utcH, tz.timezone) });
              }
            });
            if (richZones.length > 0) {
              slots.push({ cstHour: cstH, count: richZones.length, zones: richZones });
            }
          }

          const total = timezones.length;
          let best = slots.filter(s => s.count === total);
          if (best.length === 0) best = slots.sort((a, b) => b.count - a.count).slice(0, 6);
          else best = best.slice(0, 6);

          const qualityOf = (count) => {
            const ratio = count / total;
            if (ratio === 1) return 'excellent';
            if (ratio >= 0.66) return 'good';
            return 'weak';
          };
          const labelOf = (count) => {
            const ratio = count / total;
            if (ratio === 1) return 'Everyone synced';
            return `${count}/${total} online`;
          };

          meetingsEl.innerHTML = best.map(slot => {
            const cstLabel = `${String(slot.cstHour).padStart(2, '0')}:00`;
            const quality = qualityOf(slot.count);
            const chips = slot.zones.map(z =>
              `<span class="wtb-meeting-zone-chip">${z.tz.flag} ${z.localTime}</span>`
            ).join('');
            return `
              <div class="wtb-meeting-card">
                <span class="wtb-meeting-quality ${quality}">${labelOf(slot.count)}</span>
                <div class="wtb-meeting-time">${cstLabel} CST</div>
                <div class="wtb-meeting-zones">${chips}</div>
              </div>
            `;
          }).join('');
        }

        // ---------- Init + tickers ----------
        function renderAll() {
          renderGrid();
          renderNowCursor();
          renderCoverage();
          renderMeetings();
        }

        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', renderAll);
        } else {
          renderAll();
        }

        // Refresh now cursor every 30s; tracks / coverage / meetings every minute.
        setInterval(renderNowCursor, 30 * 1000);
        setInterval(() => {
          renderCoverage();
          renderMeetings();
        }, 60 * 1000);

        // Hook into add/remove timezone — replay original + repaint WTB
        const origUpdate = window.updateAllClocks;
        window.updateAllClocks = function () {
          if (typeof origUpdate === 'function') origUpdate.apply(this, arguments);
          renderAll();
        };
      })();
    </script>

    <!-- ============================================================
         Hour Explorer module — WTB-style hover/drag selector
         Reads timezones; independent of the WTB grid above.
         ============================================================ -->
    <script>
      (function () {
        'use strict';

        if (typeof timezones === 'undefined') {
          console.warn('hex module: `timezones` array not found, aborting');
          return;
        }

        const wrap     = document.getElementById('hexStripWrap');
        const strip    = document.getElementById('hexStrip');
        const ticks    = document.getElementById('hexStripTicks');
        const axis     = document.getElementById('hexStripAxis');
        const cursor   = document.getElementById('hexCursor');
        const lbl      = document.getElementById('hexCursorLabel');
        const rowsEl   = document.getElementById('hexRows');
        const metaUtc  = document.getElementById('hexMetaUtc');
        const metaDate = document.getElementById('hexMetaDate');
        const btnNow   = document.getElementById('hexNow');
        const btnMinus = document.getElementById('hexShiftMinus');
        const btnPlus  = document.getElementById('hexShiftPlus');
        if (!wrap || !strip || !rowsEl) return;

        // ---------- Helpers ----------
        function getZoneOffsetHours(tzName) {
          const probe = new Date(Date.UTC(2000, 0, 1, 0, 0, 0));
          const fmt = new Intl.DateTimeFormat('en-US', {
            timeZone: tzName, timeZoneName: 'longOffset', hour: '2-digit',
          });
          const parts = fmt.formatToParts(probe);
          const off = parts.find(p => p.type === 'timeZoneName');
          if (!off) return 0;
          const m = off.value.match(/([+\-])(\d{1,2})(?::(\d{2}))?/);
          if (!m) return 0;
          const sign = m[1] === '+' ? 1 : -1;
          const h = parseInt(m[2], 10);
          const min = parseInt(m[3] || '0', 10);
          return sign * (h + min / 60);
        }
        function utcOffsetLabel(tzName) {
          const probe = new Date(Date.UTC(2000, 0, 1, 0, 0, 0));
          const fmt = new Intl.DateTimeFormat('en-US', {
            timeZone: tzName, timeZoneName: 'shortOffset', hour: '2-digit',
          });
          const parts = fmt.formatToParts(probe);
          const off = parts.find(p => p.type === 'timeZoneName');
          return off ? off.value : '';
        }

        // Build a Date that represents `anchorHourFrac` hours since the start
        // of *today in the anchor timezone*. Anchor is China (Asia/Shanghai).
        // The horizontal axis 0..24 of the strip represents the anchor
        // timezone's hour-of-day, so this function is the geometric inverse
        // of "given the X coordinate on the strip, what's the moment?".
        const ANCHOR_TZ = 'Asia/Shanghai';

        function probeAtAnchorHour(anchorHourFrac) {
          // 1) Read today's wall-clock date in ANCHOR_TZ (year/month/day)
          const now = new Date();
          const dtf = new Intl.DateTimeFormat('en-CA', {
            timeZone: ANCHOR_TZ,
            year: 'numeric', month: '2-digit', day: '2-digit',
          });
          const parts = dtf.formatToParts(now).reduce((a, p) => (a[p.type] = p.value, a), {});
          const [y, m, day] = [parts.year, parts.month, parts.day].map(Number);
          // 2) Build the timestamp = anchor-today 00:00 + frac hours,
          //    converted to real UTC instant.
          //    China is fixed UTC+8 (no DST), so subtract 8h.
          const ANCHOR_OFFSET_HOURS = 8;
          const utcMs = Date.UTC(y, m - 1, day, 0, 0, 0)
                       - ANCHOR_OFFSET_HOURS * 3600 * 1000
                       + anchorHourFrac * 3600 * 1000;
          return new Date(utcMs);
        }

        // Read the current hour-of-day in the anchor timezone as a decimal
        // fraction (e.g. 14.5 = 14:30). Used by `btnNow`.
        function currentAnchorHourFrac() {
          const now = new Date();
          const fmt = new Intl.DateTimeFormat('en-GB', {
            timeZone: ANCHOR_TZ,
            hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
          });
          const parts = fmt.formatToParts(now);
          const hh = parseInt(parts.find(p => p.type === 'hour').value, 10);
          const mm = parseInt(parts.find(p => p.type === 'minute').value, 10);
          const ss = parseInt(parts.find(p => p.type === 'second').value, 10);
          return (hh % 24) + mm / 60 + ss / 3600;
        }

        // Format HH:MM (24-hour) in the given zone for `date`.
        function formatClock24(date, tzName) {
          // 24-hour, no AM/PM. Use en-GB which by convention renders 24h.
          return new Intl.DateTimeFormat('en-GB', {
            hour: '2-digit', minute: '2-digit', hour12: false, timeZone: tzName,
          }).format(date);
        }

        function formatWeekday(date, tzName) {
          return new Intl.DateTimeFormat('en-US', {
            weekday: 'short', timeZone: tzName,
          }).format(date);
        }

        function formatCalendar(date, tzName) {
          return new Intl.DateTimeFormat('en-US', {
            month: 'long', day: 'numeric', timeZone: tzName,
          }).format(date);
        }

        function inWorkingHours(localHour, workingHours, isCurrent) {
          const [s, e] = workingHours;
          const [h, m] = [Math.floor(localHour), (localHour % 1) * 60];
          // Treat `localHour` as decimal hours; working window is integer
          // hours so a value at 17.5 is "still in working hours if start<17.5<18".
          const lv = h + (m >= 30 ? 0.5 : 0); // snap to 0.5h ticks
          if (isCurrent) return 'current';
          // Mid-hour 0.5 means same status as :00 hour
          const baseH = Math.floor(lv);
          return (baseH >= s && baseH < e) ? 'working' : 'off';
        }

        function getLocalHourAt(probeDate, tzName) {
          const fmt = new Intl.DateTimeFormat('en-US', {
            hour: '2-digit', minute: '2-digit', hour12: false, timeZone: tzName,
          });
          const parts = fmt.formatToParts(probeDate);
          const hh = parseInt(parts.find(p => p.type === 'hour').value, 10);
          const mm = parseInt(parts.find(p => p.type === 'minute').value, 10);
          // Reduce 24:00 to 0:00
          return ((hh % 24) + mm / 60);
        }

        // ---------- Build the static strip skeleton (ticks + axis) ----------
        function buildStrip() {
          ticks.innerHTML = Array.from({ length: 24 }, (_, i) => {
            const major = i % 6 === 0 ? ' major' : '';
            return `<div class="hex-strip-tick${major}"></div>`;
          }).join('');
          axis.innerHTML = Array.from({ length: 24 }, (_, i) => {
            const major = i % 6 === 0 ? ' major' : '';
            const label = String(i).padStart(2, '0');
            return `<span class="hex-strip-axis-tick${major}" style="left:${(i / 24) * 100}%">${label}</span>`;
          }).join('');
        }

        // ---------- Per-zone rows (labels) ----------
        function buildRows() {
          rowsEl.innerHTML = timezones.map(tz => {
            const offset = getZoneOffsetHours(tz.timezone);
            const offLbl = utcOffsetLabel(tz.timezone);
            return `
              <div class="hex-row-label">
                <span class="hex-row-flag">${tz.flag}</span>
                <span class="hex-row-name">${tz.name}</span>
                <span class="hex-row-offset" title="UTC ${offset >= 0 ? '+' : ''}${offset}">${offLbl}</span>
              </div>
              <div class="hex-row-time" data-tz="${tz.timezone}" data-offset="${offset}" data-current="${!!tz.isCurrent}">
                <div class="hex-row-clock">--:--</div>
                <div class="hex-row-date"></div>
                <span class="hex-row-status"></span>
              </div>
            `;
          }).join('');
        }

        // ---------- Cursor + per-row live updates ----------
        // `referenceDate` is a real UTC instant whose anchor-tz HH:MM is
        // what the user is "exploring". Horizontal axis 0..24 = anchor
        // timezone's hour-of-day.
        let referenceDate = probeAtAnchorHour(currentAnchorHourFrac());

        // ---- Read hour/minute/second of `referenceDate` *as seen in* a
        // given timezone. We use this in many places so centralise it.
        function partsInZone(date, tzName) {
          const fmt = new Intl.DateTimeFormat('en-GB', {
            timeZone: tzName,
            hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
          });
          const p = fmt.formatToParts(date);
          const hh = parseInt(p.find(x => x.type === 'hour').value, 10);
          const mm = parseInt(p.find(x => x.type === 'minute').value, 10);
          const ss = parseInt(p.find(x => x.type === 'second').value, 10);
          return { hh: hh % 24, mm, ss };
        }

        function placeCursor() {
          // Position on the 0..24 axis is the anchor-tz hour of day.
          const p = partsInZone(referenceDate, ANCHOR_TZ);
          const frac = p.hh + p.mm / 60 + p.ss / 3600;
          const pctRaw = (frac / 24) * 100;
          const stripWidth = strip.getBoundingClientRect().width;
          if (!stripWidth) return;
          cursor.style.left = `calc(${pctRaw}% )`;
          cursor.style.display = 'block';
          lbl.textContent = `${String(p.hh).padStart(2, '0')}:${String(p.mm).padStart(2, '0')} CST`;
        }

        function updateRows() {
          // Meta header — reference time expressed in ANCHOR_TZ (China)
          const p = partsInZone(referenceDate, ANCHOR_TZ);
          metaUtc.textContent =
            `${String(p.hh).padStart(2, '0')}:${String(p.mm).padStart(2, '0')} CST`;

          // Header date in anchor timezone (so it changes at midnight CST,
          // not at midnight UTC).
          const fmt = new Intl.DateTimeFormat('en-US', {
            weekday: 'long', month: 'long', day: 'numeric', timeZone: ANCHOR_TZ,
          });
          metaDate.textContent = fmt.format(referenceDate);

          // Per-zone rows
          rowsEl.querySelectorAll('.hex-row-time').forEach(rowEl => {
            const tz = rowEl.getAttribute('data-tz');
            const isCurrent = rowEl.getAttribute('data-current') === 'true';
            const localHour = getLocalHourAt(referenceDate, tz);

            const clockEl = rowEl.querySelector('.hex-row-clock');
            const dateEl = rowEl.querySelector('.hex-row-date');
            const statusEl = rowEl.querySelector('.hex-row-status');

            // 24-hour HH:MM
            const tFmt = new Intl.DateTimeFormat('en-GB', {
              hour: '2-digit', minute: '2-digit', hour12: false, timeZone: tz,
            });
            clockEl.textContent = tFmt.format(referenceDate);

            // Wkd + date
            const dateText = `${formatWeekday(referenceDate, tz)} · ${formatCalendar(referenceDate, tz)}`;
            dateEl.textContent = dateText;

            // Status pill — uses workingHours via DOM lookup, but we don't
            // have access to it here. The "current" badge is shown only for
            // the timezones flagged isCurrent=true in the data.
            // Working/off logic: we re-derive from `tz.workingHours` set on
            // window.timezones.
            const tzData = (window.timezones || []).find(z => z.timezone === tz);
            let status = 'off';
            let statusText = 'Off hours';
            if (tzData) {
              const lv = Math.floor(localHour);
              const [s, e] = tzData.workingHours;
              if (isCurrent) {
                status = 'current';
                statusText = 'Current zone';
              } else if (lv >= s && lv < e) {
                status = 'working';
                statusText = 'Working hours';
              } else {
                statusText = 'Off hours';
              }
            }
            statusEl.className = `hex-row-status ${status}`;
            statusEl.textContent = statusText;
          });
        }

        function renderAll() {
          placeCursor();
          updateRows();
        }

        // ---------- Drag interaction ----------
        let dragging = false;

        function setReferenceFromEvent(e) {
          const rect = strip.getBoundingClientRect();
          const x = Math.max(0, Math.min(rect.width, (e.clientX || (e.touches && e.touches[0].clientX)) - rect.left));
          // The strip's X axis 0..24 represents ANCHOR_TZ hour-of-day.
          const anchorFrac = (x / rect.width) * 24;
          // Snap to nearest minute
          const totalMinutes = Math.round(anchorFrac * 60);
          referenceDate = probeAtAnchorHour(totalMinutes / 60);
          renderAll();
        }

        strip.addEventListener('mousedown', (e) => {
          dragging = true;
          setReferenceFromEvent(e);
        });
        document.addEventListener('mousemove', (e) => {
          if (!dragging) return;
          setReferenceFromEvent(e);
        });
        document.addEventListener('mouseup', () => { dragging = false; });

        // Touch support (single finger drag)
        strip.addEventListener('touchstart', (e) => {
          dragging = true;
          setReferenceFromEvent(e);
        }, { passive: true });
        document.addEventListener('touchmove', (e) => {
          if (!dragging) return;
          setReferenceFromEvent(e);
        }, { passive: true });
        document.addEventListener('touchend', () => { dragging = false; });

        // Hover preview — only when not dragging, so it doesn't fight drags
        let hoverActive = false;
        strip.addEventListener('mousemove', (e) => {
          if (dragging || hoverActive) return;
          hoverActive = true;
          setReferenceFromEvent(e);
          // Small debounce via rAF
          requestAnimationFrame(() => { hoverActive = false; });
        });
        strip.addEventListener('mouseleave', () => {
          // Mouse left — don't snap back; the last hover stays.
        });

        // ---------- Buttons ----------
        function shiftBy(deltaHours) {
          const p = partsInZone(referenceDate, ANCHOR_TZ);
          const cur = p.hh + p.mm / 60;
          const nextFrac = ((cur + deltaHours) % 24 + 24) % 24;
          referenceDate = probeAtAnchorHour(nextFrac);
          renderAll();
        }
        btnMinus.addEventListener('click', () => shiftBy(-1));
        btnPlus.addEventListener('click', () => shiftBy(1));
        btnNow.addEventListener('click', () => {
          // "Now" = current wall-clock hour in anchor timezone (China).
          referenceDate = probeAtAnchorHour(currentAnchorHourFrac());
          renderAll();
        });

        // Keep header meta fresh on second-level ticks so the label
        // doesn't drift away from the displayed cursor.
        setInterval(() => {
          const p = partsInZone(referenceDate, ANCHOR_TZ);
          metaUtc.textContent =
            `${String(p.hh).padStart(2, '0')}:${String(p.mm).padStart(2, '0')} CST`;
          // Re-anchor meta date when anchor-day flips (midnight CST).
          const fmt = new Intl.DateTimeFormat('en-US', {
            weekday: 'long', month: 'long', day: 'numeric', timeZone: ANCHOR_TZ,
          });
          metaDate.textContent = fmt.format(referenceDate);
        }, 1000);

        // Reposition cursor on resize (placeCursor uses getBoundingClientRect)
        window.addEventListener('resize', placeCursor);

        // ---------- Init ----------
        function init() {
          buildStrip();
          buildRows();
          // Wait one frame so layout widths are stable before initial placement
          requestAnimationFrame(renderAll);
        }
        if (document.readyState === 'loading') {
          document.addEventListener('DOMContentLoaded', init);
        } else {
          init();
        }

        // When the user adds/removes a timezone via the original addCustom-
        // Timezone / removeTimezone path, we re-build rows + re-paint.
        // `window.updateAllClocks` may already be wrapped by the WTB module
        // loaded earlier in the document — capture that wrapper here and
        // chain to it so both modules stay in sync.
        const origUpdate = window.updateAllClocks;
        window.updateAllClocks = function () {
          if (typeof origUpdate === 'function') origUpdate.apply(this, arguments);
          buildRows();
          renderAll();
        };
      })();
    </script>
  </body>
</html>
