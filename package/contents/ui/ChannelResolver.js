.pragma library

var ID_PATTERN = /^UC[A-Za-z0-9_-]{22}$/;

function directId(raw) {
    var text = String(raw || "").trim();
    if (ID_PATTERN.test(text)) return text;
    var match = text.match(/(?:[?&]channel_id=|\/channel\/)(UC[A-Za-z0-9_-]{22})(?=$|[/?&#])/i);
    return match ? match[1] : "";
}

function resolveHandleUrl(raw) {
    var text = String(raw || "").trim();
    if (/^@[A-Za-z0-9._-]+$/.test(text)) return "https://www.youtube.com/" + text;
    var match = text.match(/^https?:\/\/(?:www\.|m\.)?youtube\.com\/(?:@([A-Za-z0-9._-]+)|c\/([A-Za-z0-9._-]+)|user\/([A-Za-z0-9._-]+))(?:[/?#].*)?$/i);
    if (match) return "https://www.youtube.com/" +
                       (match[1] ? "@" + match[1] : (match[2] ? "c/" + match[2] : "user/" + match[3]));
    return "";
}

function displayLabel(raw, fallbackId) {
    var text = String(raw || "").trim();
    var match = text.match(/(?:^|\/)@([A-Za-z0-9._-]+)/);
    if (match) return "@" + match[1];
    match = text.match(/\/((?:c|user)\/)([A-Za-z0-9._-]+)/);
    if (match) return match[2];
    return fallbackId;
}

// This must identify the *owner* of the channel page. Generic "channelId"
// keys and arbitrary /channel/ URLs are UNSAFE: YouTube pages can mention
// many unrelated channels (featured/recommended channels, collaborations).
function htmlAttribute(tag, name) {
    var match = String(tag).match(new RegExp("(?:^|\\s)" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", "i"));
    return match ? (match[1] || match[2] || match[3] || "") : "";
}

function idFromHtml(html) {
    var content = String(html || "");
    var tags = content.match(/<(?:link|meta)\b[^>]*>/gi) || [];
    var feedId = "";
    var canonicalId = "";
    var itemId = "";
    for (var i = 0; i < tags.length; i++) {
        var tag = tags[i];
        var href = htmlAttribute(tag, "href");
        var urlId = directId(href);
        var rel = htmlAttribute(tag, "rel").toLowerCase();
        var property = htmlAttribute(tag, "property").toLowerCase();
        var contentAttr = htmlAttribute(tag, "content");
        if (rel.indexOf("alternate") !== -1 && /youtube\.com\/feeds\/videos\.xml\?/i.test(href) && urlId) {
            feedId = urlId;
        }
        if (rel.indexOf("canonical") !== -1 && /youtube\.com\/channel\//i.test(href) && urlId) {
            canonicalId = urlId;
        }
        if (htmlAttribute(tag, "itemprop").toLowerCase() === "channelid" && ID_PATTERN.test(contentAttr)) {
            itemId = contentAttr;
        }
        if (property === "og:url" && /youtube\.com\/channel\//i.test(contentAttr)) {
            var ogId = directId(contentAttr);
            if (ogId && !canonicalId) canonicalId = ogId;
        }
    }
    // These elements describe the current page, unlike arbitrary channel links.
    if (canonicalId) return canonicalId;
    if (feedId) return feedId;
    if (itemId) return itemId;
    // channelMetadataRenderer.externalId specifically identifies page owner.
    var metadata = content.match(/"channelMetadataRenderer"\s*:\s*\{[^}]*"externalId"\s*:\s*"(UC[A-Za-z0-9_-]{22})"/);
    if (metadata) return metadata[1];
    // Last resort: externalId is normally the page owner's unique identifier.
    var external = content.match(/"externalId"\s*:\s*"(UC[A-Za-z0-9_-]{22})"/);
    return external ? external[1] : "";
}
