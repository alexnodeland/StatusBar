// StatusBar Landing Page — Minimal JS
// Mobile nav, smooth scroll, copy buttons, collapsible, active nav

(function () {
  'use strict';

  // --- Mobile nav toggle ---
  const toggle = document.getElementById('nav-toggle');
  const links = document.getElementById('nav-links');

  if (toggle && links) {
    toggle.addEventListener('click', function () {
      links.classList.toggle('open');
    });

    // Close mobile nav when a link is clicked
    links.addEventListener('click', function (e) {
      if (e.target.tagName === 'A') {
        links.classList.remove('open');
      }
    });
  }

  // --- Smooth scroll for anchor links ---
  document.querySelectorAll('a[href^="#"]').forEach(function (anchor) {
    anchor.addEventListener('click', function (e) {
      const target = document.querySelector(this.getAttribute('href'));
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth' });
      }
    });
  });

  // --- Copy-to-clipboard on code blocks ---
  document.querySelectorAll('.copy-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      const code = this.parentElement.querySelector('code');
      if (!code) return;
      navigator.clipboard.writeText(code.textContent).then(function () {
        btn.textContent = 'Copied!';
        setTimeout(function () {
          btn.textContent = 'Copy';
        }, 1500);
      }).catch(function () {
        btn.textContent = 'Failed';
        setTimeout(function () {
          btn.textContent = 'Copy';
        }, 1500);
      });
    });
  });

  // --- Collapsible sections ---
  const trigger = document.getElementById('build-trigger');
  const content = document.getElementById('build-content');

  if (trigger && content) {
    trigger.addEventListener('click', function () {
      trigger.classList.toggle('open');
      content.classList.toggle('open');
    });
  }

  // --- Source Directory ---
  var STATUS_SOURCES = [
    // AI & Technology
    { name: 'Anthropic', url: 'https://status.anthropic.com', category: 'AI & Technology' },
    { name: 'OpenAI', url: 'https://status.openai.com', category: 'AI & Technology' },
    { name: 'Hugging Face', url: 'https://status.huggingface.co', category: 'AI & Technology' },
    { name: 'Stability AI', url: 'https://status.stability.ai', category: 'AI & Technology' },
    { name: 'Perplexity', url: 'https://status.perplexity.ai', category: 'AI & Technology' },
    { name: 'Cohere', url: 'https://status.cohere.com', category: 'AI & Technology' },
    { name: 'Mistral', url: 'https://status.mistral.ai', category: 'AI & Technology' },
    // Developer Platforms
    { name: 'GitHub', url: 'https://www.githubstatus.com', category: 'Developer Platforms' },
    { name: 'Atlassian', url: 'https://status.atlassian.com', category: 'Developer Platforms' },
    { name: 'Bitbucket', url: 'https://bitbucket.status.atlassian.com', category: 'Developer Platforms' },
    { name: 'GitLab', url: 'https://status.gitlab.com', category: 'Developer Platforms' },
    { name: 'Linear', url: 'https://linearstatus.com', category: 'Developer Platforms' },
    { name: 'Vercel', url: 'https://www.vercel-status.com', category: 'Developer Platforms' },
    { name: 'Netlify', url: 'https://www.netlifystatus.com', category: 'Developer Platforms' },
    { name: 'Render', url: 'https://status.render.com', category: 'Developer Platforms' },
    { name: 'Railway', url: 'https://status.railway.com', category: 'Developer Platforms' },
    { name: 'Zed', url: 'https://status.zed.dev', category: 'Developer Platforms' },
    { name: 'Deno', url: 'https://denostatus.com', category: 'Developer Platforms' },
    { name: 'Fly.io', url: 'https://status.flyio.net', category: 'Developer Platforms' },
    { name: 'Heroku', url: 'https://status.heroku.com', category: 'Developer Platforms' },
    { name: 'npm', url: 'https://status.npmjs.org', category: 'Developer Platforms' },
    { name: 'CircleCI', url: 'https://status.circleci.com', category: 'Developer Platforms' },
    { name: 'Codecov', url: 'https://status.codecov.io', category: 'Developer Platforms' },
    // Cloud & CDN
    { name: 'Cloudflare', url: 'https://www.cloudflarestatus.com', category: 'Cloud & CDN' },
    { name: 'Fastly', url: 'https://status.fastly.com', category: 'Cloud & CDN' },
    { name: 'DigitalOcean', url: 'https://status.digitalocean.com', category: 'Cloud & CDN' },
    { name: 'Linode', url: 'https://status.linode.com', category: 'Cloud & CDN' },
    { name: 'Vultr', url: 'https://status.vultr.com', category: 'Cloud & CDN' },
    // Monitoring & Observability
    { name: 'Datadog', url: 'https://status.datadoghq.com', category: 'Monitoring & Observability' },
    { name: 'PagerDuty', url: 'https://status.pagerduty.com', category: 'Monitoring & Observability' },
    { name: 'New Relic', url: 'https://status.newrelic.com', category: 'Monitoring & Observability' },
    { name: 'Sentry', url: 'https://status.sentry.io', category: 'Monitoring & Observability' },
    { name: 'Statuspage', url: 'https://metastatuspage.com', category: 'Monitoring & Observability' },
    // Communication
    { name: 'Slack', url: 'https://status.slack.com', category: 'Communication' },
    { name: 'Discord', url: 'https://discordstatus.com', category: 'Communication' },
    { name: 'Zoom', url: 'https://status.zoom.us', category: 'Communication' },
    { name: 'Twilio', url: 'https://status.twilio.com', category: 'Communication' },
    { name: 'Loom', url: 'https://www.loomstatus.com', category: 'Communication' },
    // Productivity
    { name: 'Todoist', url: 'https://status.todoist.net', category: 'Productivity' },
    { name: 'Notion', url: 'https://status.notion.so', category: 'Productivity' },
    { name: 'Figma', url: 'https://status.figma.com', category: 'Productivity' },
    { name: 'Miro', url: 'https://status.miro.com', category: 'Productivity' },
    { name: 'Airtable', url: 'https://status.airtable.com', category: 'Productivity' },
    { name: 'Asana', url: 'https://trust.asana.com', category: 'Productivity' },
    { name: 'Monday.com', url: 'https://status.monday.com', category: 'Productivity' },
    { name: 'ClickUp', url: 'https://clickup.statuspage.io', category: 'Productivity' },
    { name: 'Coda', url: 'https://status.coda.io', category: 'Productivity' },
    { name: '1Password', url: 'https://status.1password.com', category: 'Productivity' },
    // E-commerce & Payments
    { name: 'Stripe', url: 'https://status.stripe.com', category: 'E-commerce & Payments' },
    { name: 'Shopify', url: 'https://status.shopify.com', category: 'E-commerce & Payments' },
    { name: 'Square', url: 'https://issquareup.com', category: 'E-commerce & Payments' },
    { name: 'Braintree', url: 'https://status.braintreepayments.com', category: 'E-commerce & Payments' },
    // Email & Marketing
    { name: 'SendGrid', url: 'https://status.sendgrid.com', category: 'Email & Marketing' },
    { name: 'Mailchimp', url: 'https://status.mailchimp.com', category: 'Email & Marketing' },
    { name: 'Postmark', url: 'https://status.postmarkapp.com', category: 'Email & Marketing' },
    { name: 'Mailgun', url: 'https://status.mailgun.com', category: 'Email & Marketing' },
    // Data & Analytics
    { name: 'Segment', url: 'https://status.segment.com', category: 'Data & Analytics' },
    { name: 'Amplitude', url: 'https://status.amplitude.com', category: 'Data & Analytics' },
    { name: 'Mixpanel', url: 'https://status.mixpanel.com', category: 'Data & Analytics' },
    { name: 'Snowflake', url: 'https://status.snowflake.com', category: 'Data & Analytics' },
    // Databases
    { name: 'MongoDB Atlas', url: 'https://status.cloud.mongodb.com', category: 'Databases' },
    { name: 'PlanetScale', url: 'https://www.planetscalestatus.com', category: 'Databases' },
    { name: 'Supabase', url: 'https://status.supabase.com', category: 'Databases' },
    { name: 'Redis Cloud', url: 'https://status.redis.io', category: 'Databases' },
    { name: 'Neon', url: 'https://neonstatus.com', category: 'Databases' },
    // Customer Support & CRM
    { name: 'Zendesk', url: 'https://status.zendesk.com', category: 'Customer Support & CRM' },
    { name: 'Intercom', url: 'https://www.intercomstatus.com', category: 'Customer Support & CRM' },
    { name: 'HubSpot', url: 'https://status.hubspot.com', category: 'Customer Support & CRM' },
    // Security & Auth
    { name: 'Okta', url: 'https://status.okta.com', category: 'Security & Auth' },
    { name: 'Auth0', url: 'https://status.auth0.com', category: 'Security & Auth' },
    { name: 'HashiCorp', url: 'https://status.hashicorp.com', category: 'Security & Auth' },
    // Media & Entertainment
    { name: 'Spotify', url: 'https://status.spotify.dev', category: 'Media & Entertainment' },
    { name: 'Vimeo', url: 'https://status.vimeo.com', category: 'Media & Entertainment' }
  ];

  var selectedUrls = new Set();

  function escapeHtml(str) {
    var div = document.createElement('div');
    div.appendChild(document.createTextNode(str));
    return div.innerHTML;
  }

  function escapeAttr(str) {
    return str.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function downloadJSON(filename, content) {
    var blob = new Blob([content], { type: 'application/json;charset=utf-8' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(a.href);
  }

  function renderSources(filter) {
    var listEl = document.getElementById('source-list');
    var countEl = document.getElementById('source-count');
    var selectAllEl = document.getElementById('source-select-all');
    var exportBtn = document.getElementById('source-export');
    if (!listEl) return;

    var lowerFilter = (filter || '').toLowerCase();
    var filtered = STATUS_SOURCES.filter(function (s) {
      return !lowerFilter || s.name.toLowerCase().indexOf(lowerFilter) !== -1 || s.url.toLowerCase().indexOf(lowerFilter) !== -1;
    });

    // Group by category preserving order
    var groups = [];
    var groupMap = {};
    filtered.forEach(function (s) {
      if (!groupMap[s.category]) {
        groupMap[s.category] = [];
        groups.push({ category: s.category, items: groupMap[s.category] });
      }
      groupMap[s.category].push(s);
    });

    if (filtered.length === 0) {
      listEl.innerHTML = '<div class="source-empty">No services match your search.</div>';
    } else {
      var html = '';
      groups.forEach(function (g) {
        html += '<div class="source-category">' + escapeHtml(g.category) + '</div>';
        g.items.forEach(function (s) {
          var checked = selectedUrls.has(s.url) ? ' checked' : '';
          var selectedClass = selectedUrls.has(s.url) ? ' selected' : '';
          html += '<div class="source-item' + selectedClass + '" role="listitem" data-url="' + escapeAttr(s.url) + '">'
            + '<span class="source-check" role="checkbox" aria-checked="' + (selectedUrls.has(s.url) ? 'true' : 'false') + '" aria-label="Select ' + escapeAttr(s.name) + '"><svg width="10" height="10" viewBox="0 0 10 10" fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M2 5l2.5 2.5L8 3"/></svg></span>'
            + '<span class="source-item-name">' + escapeHtml(s.name) + '</span>'
            + '<span class="source-item-url">' + escapeHtml(s.url) + '</span>'
            + '<button class="source-copy-btn" data-copy="' + escapeAttr(s.url) + '" aria-label="Copy URL">Copy</button>'
            + '</div>';
        });
      });
      listEl.innerHTML = html;
    }

    // Count
    if (countEl) {
      countEl.textContent = filtered.length + ' of ' + STATUS_SOURCES.length + ' services';
    }

    // Select-all state
    var selectAllLabel = document.getElementById('source-select-all-label');
    if (selectAllEl && selectAllLabel) {
      var visibleSelected = filtered.filter(function (s) { return selectedUrls.has(s.url); }).length;
      selectAllLabel.classList.remove('checked', 'indeterminate');
      if (visibleSelected === 0) {
        selectAllEl.checked = false;
      } else if (visibleSelected === filtered.length) {
        selectAllEl.checked = true;
        selectAllLabel.classList.add('checked');
      } else {
        selectAllEl.checked = false;
        selectAllLabel.classList.add('indeterminate');
      }
    }

    // Export button
    if (exportBtn) {
      exportBtn.disabled = selectedUrls.size === 0;
      if (selectedUrls.size > 0) {
        exportBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M8 2v8m0 0L5 7m3 3 3-3M3 12h10"/></svg> Export ' + selectedUrls.size + ' as JSON';
      } else {
        exportBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M8 2v8m0 0L5 7m3 3 3-3M3 12h10"/></svg> Export JSON';
      }
    }
  }

  // Event handlers for source directory
  var searchInput = document.getElementById('source-search');
  var sourceList = document.getElementById('source-list');
  var selectAllCheckbox = document.getElementById('source-select-all');
  var exportButton = document.getElementById('source-export');

  if (searchInput) {
    var debounceTimer;
    searchInput.addEventListener('input', function () {
      clearTimeout(debounceTimer);
      var val = searchInput.value;
      debounceTimer = setTimeout(function () {
        renderSources(val);
      }, 120);
    });

    searchInput.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') {
        searchInput.value = '';
        searchInput.blur();
        renderSources('');
      }
    });
  }

  if (sourceList) {
    sourceList.addEventListener('click', function (e) {
      // Copy button
      var copyBtn = e.target.closest('.source-copy-btn');
      if (copyBtn) {
        var url = copyBtn.getAttribute('data-copy');
        navigator.clipboard.writeText(url).then(function () {
          copyBtn.textContent = 'Copied!';
          setTimeout(function () { copyBtn.textContent = 'Copy'; }, 1500);
        }).catch(function () {
          copyBtn.textContent = 'Failed';
          setTimeout(function () { copyBtn.textContent = 'Copy'; }, 1500);
        });
        return;
      }

      // Row toggle
      var item = e.target.closest('.source-item');
      if (item) {
        var url = item.getAttribute('data-url');
        if (selectedUrls.has(url)) {
          selectedUrls.delete(url);
        } else {
          selectedUrls.add(url);
        }
        renderSources(searchInput ? searchInput.value : '');
      }
    });
  }

  if (selectAllCheckbox) {
    selectAllCheckbox.addEventListener('change', function () {
      var lowerFilter = (searchInput ? searchInput.value : '').toLowerCase();
      var visible = STATUS_SOURCES.filter(function (s) {
        return !lowerFilter || s.name.toLowerCase().indexOf(lowerFilter) !== -1 || s.url.toLowerCase().indexOf(lowerFilter) !== -1;
      });
      if (selectAllCheckbox.checked) {
        visible.forEach(function (s) { selectedUrls.add(s.url); });
      } else {
        visible.forEach(function (s) { selectedUrls.delete(s.url); });
      }
      renderSources(searchInput ? searchInput.value : '');
    });
  }

  if (exportButton) {
    exportButton.addEventListener('click', function () {
      if (selectedUrls.size === 0) return;
      var sources = [];
      STATUS_SOURCES.forEach(function (s) {
        if (selectedUrls.has(s.url)) {
          sources.push({
            id: crypto.randomUUID(),
            name: s.name,
            baseURL: s.url,
            alertLevel: 'All Changes',
            sortOrder: sources.length
          });
        }
      });
      downloadJSON('statusbar-sources.json', JSON.stringify(sources, null, 2));
    });
  }

  // Initial render
  renderSources('');

  // --- IntersectionObserver for active nav link ---
  const sections = document.querySelectorAll('section[id]');
  const navLinks = document.querySelectorAll('.nav-links a[href^="#"]');

  if (sections.length && navLinks.length && 'IntersectionObserver' in window) {
    const observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            const id = entry.target.getAttribute('id');
            navLinks.forEach(function (link) {
              link.classList.toggle(
                'active',
                link.getAttribute('href') === '#' + id
              );
            });
          }
        });
      },
      { rootMargin: '-30% 0px -70% 0px' }
    );

    sections.forEach(function (section) {
      observer.observe(section);
    });
  }
})();
