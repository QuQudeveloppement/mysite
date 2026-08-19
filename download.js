/* ==========================================================================
   download.js — empaquette chaque fichier téléchargé avec le README de
   licence, généré à la volée dans le navigateur (JSZip), sans serveur.
   ========================================================================== */

const LICENSE_README = `Project: Arduino Code by Quentin
Website: https://ququdeveloppement.github.io/mysite/

Copyright (c) 2026 Quentin
All rights reserved.

You are allowed to:
- Download and test this code on your own hardware.

You are NOT allowed to:
- Redistribute this code.
- Upload it to another website.
- Claim it as your own.
- Modify it and publish it elsewhere.

If you want to use this code in a project or video, you MUST credit:
"Code created by Quentin – ququdeveloppement.github.io/mysite/"
`;

async function handleFileDownloadClick(btn) {
  const url = btn.dataset.fileUrl;
  const filename = btn.dataset.fileName || url.split("/").pop();
  const originalHtml = btn.innerHTML;

  if (typeof JSZip === "undefined") {
    alert("Le module de compression n'a pas pu se charger. Vérifie ta connexion et réessaie.");
    return;
  }

  btn.disabled = true;
  btn.textContent = "Préparation du ZIP…";
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error("Fichier introuvable sur le serveur");
    const blob = await res.blob();

    const zip = new JSZip();
    zip.file(filename, blob);
    zip.file("README.md", LICENSE_README);
    const zipBlob = await zip.generateAsync({ type: "blob" });

    const zipName = filename.replace(/\.[^.]+$/, "") + ".zip";
    const link = document.createElement("a");
    link.href = URL.createObjectURL(zipBlob);
    link.download = zipName;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(link.href), 4000);
  } catch (err) {
    alert("Erreur lors du téléchargement : " + err.message);
  } finally {
    btn.disabled = false;
    btn.innerHTML = originalHtml;
  }
}

document.addEventListener("click", (e) => {
  const btn = e.target.closest(".js-download-file");
  if (btn) {
    e.preventDefault();
    handleFileDownloadClick(btn);
  }
});
