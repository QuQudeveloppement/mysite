/* ==========================================================================
   render.js — transforme un article (JSON, structure en "blocs") en HTML.
   Utilisé par index.html (lecture publique) et admin.html (aperçu).
   ========================================================================== */

function escapeHtml(str = "") {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

// Gras/italique très simple : **gras** et *italique*, sans dépendance externe.
function inlineFormat(str = "") {
  let out = escapeHtml(str);
  out = out.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
  out = out.replace(/\*(.+?)\*/g, "<em>$1</em>");
  out = out.replace(/\n/g, "<br>");
  return out;
}

function videoEmbedHtml(url) {
  const yt = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([\w-]+)/);
  if (yt) {
    return `<div class="media-frame"><iframe src="https://www.youtube.com/embed/${yt[1]}"
      title="Vidéo" loading="lazy" allowfullscreen
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"></iframe></div>`;
  }
  const vimeo = url.match(/vimeo\.com\/(\d+)/);
  if (vimeo) {
    return `<div class="media-frame"><iframe src="https://player.vimeo.com/video/${vimeo[1]}"
      title="Vidéo" loading="lazy" allowfullscreen></iframe></div>`;
  }
  // Fichier vidéo direct (mp4, webm...)
  return `<div class="media-frame"><video controls preload="metadata" src="${url}"></video></div>`;
}

function renderBlock(block) {
  switch (block.type) {
    case "heading":
      return `<h3 class="block-heading">${escapeHtml(block.value)}</h3>`;
    case "text":
      return `<p class="block-text">${inlineFormat(block.value)}</p>`;
    case "image":
      return `<figure class="block-image">
        <img src="${block.url}" alt="${escapeHtml(block.alt || "")}" loading="lazy">
        ${block.caption ? `<figcaption>${escapeHtml(block.caption)}</figcaption>` : ""}
      </figure>`;
    case "video":
      return `<figure class="block-video">
        ${videoEmbedHtml(block.url)}
        ${block.caption ? `<figcaption>${escapeHtml(block.caption)}</figcaption>` : ""}
      </figure>`;
    case "code":
      return `<pre class="block-code"><code>${escapeHtml(block.value)}</code></pre>`;
    case "file": {
      const label = block.label || block.filename || "le fichier";
      const filename = escapeHtml(block.filename || (block.url || "").split("/").pop());
      return `<div class="block-file">
        <button type="button" class="btn js-download-file" data-file-url="${block.url}" data-file-name="${filename}">
          ⬇ Télécharger ${escapeHtml(label)} (.zip)
        </button>
        ${block.caption ? `<p class="field-hint">${escapeHtml(block.caption)}</p>` : ""}
      </div>`;
    }
    default:
      return "";
  }
}

function renderArticleBody(article) {
  return (article.blocks || []).map(renderBlock).join("\n");
}

function formatDate(iso) {
  try {
    const d = new Date(iso + "T00:00:00");
    return d.toLocaleDateString("fr-FR", { day: "2-digit", month: "long", year: "numeric" });
  } catch {
    return iso;
  }
}

/* ---------------------------------------------------------------------
   Archivage — calculé à la volée (pas de tâche planifiée possible sur un
   site statique). Règles, dans l'ordre de priorité :
   1. archivedManually === true  -> toujours archivé
   2. keepActive === true        -> jamais archivé (force la sortie d'archive)
   3. archiveAfterMonths = null  -> jamais archivé automatiquement
   4. sinon, archivé dès que la date de l'article dépasse ce nombre de mois
   --------------------------------------------------------------------- */
function monthsSince(dateStr) {
  const d = new Date(dateStr + "T00:00:00");
  const now = new Date();
  let months = (now.getFullYear() - d.getFullYear()) * 12 + (now.getMonth() - d.getMonth());
  if (now.getDate() < d.getDate()) months -= 1;
  return months;
}

function isArchived(article) {
  if (article.archivedManually) return true;
  if (article.keepActive) return false;
  if (article.archiveAfterMonths === null || article.archiveAfterMonths === undefined) return false;
  return monthsSince(article.date) >= article.archiveAfterMonths;
}
