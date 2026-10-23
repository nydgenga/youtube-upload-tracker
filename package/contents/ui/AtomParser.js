.pragma library

// YouTube Atom parser for Qt QML's reduced responseXML DOM. Qt does not
// expose namespaceURI/localName; real builds can obscure namespace prefixes.
// Validate declared namespaces when possible, but never make the entire feed
// depend on a yt:videoId QName: Atom entry ids are an independent fallback.
var NS_ATOM = "http://www.w3.org/2005/Atom";
var NS_YOUTUBE = "http://www.youtube.com/xml/schemas/2015";
var NS_MEDIA = "http://search.yahoo.com/mrss/";

function attribute(node, name) {
    if (!node || !node.attributes) return "";
    var attrs = node.attributes;
    // Some DOM implementations expose getNamedItem; Qt's reduced DOM also
    // exposes the attributes collection as a NamedNodeMap-like object.
    if (typeof attrs.getNamedItem === "function") {
        var named = attrs.getNamedItem(name);
        if (named) return String(named.value !== undefined ? named.value : named.nodeValue || "");
    }
    var length = Number(attrs.length || 0);
    for (var i = 0; i < length; ++i) {
        var item = typeof attrs.item === "function" ? attrs.item(i) : attrs[i];
        if (item && String(item.name || item.nodeName) === name)
            return String(item.value !== undefined ? item.value : item.nodeValue || "");
    }
    // A few Qt DOM wrappers expose named attributes as map keys.
    if (attrs[name] && typeof attrs[name] === "object")
        return String(attrs[name].value !== undefined ? attrs[name].value : attrs[name].nodeValue || "");
    return "";
}

function declaredNamespace(node, prefix) {
    var attrName = prefix ? "xmlns:" + prefix : "xmlns";
    for (var current = node; current; current = current.parentNode) {
        var uri = attribute(current, attrName);
        if (uri) return uri;
    }
    return "";
}

function isElement(node, localName, namespace) {
    if (!node || node.nodeType !== 1) return false;
    var qualified = String(node.nodeName || "");
    var cut = qualified.indexOf(":");
    var prefix = cut >= 0 ? qualified.substring(0, cut) : "";
    var local = cut >= 0 ? qualified.substring(cut + 1) : qualified;
    if (local !== localName) return false;
    var declared = declaredNamespace(node, prefix);
    if (declared) return declared === namespace;
    // Compatibility for Qt builds whose reduced DOM does not surface xmlns
    // declarations. Do not accept arbitrary undeclared or unrelated prefixes.
    if (!prefix) return namespace === NS_ATOM;
    return (prefix === "yt" && namespace === NS_YOUTUBE) ||
           (prefix === "media" && namespace === NS_MEDIA);
}

function child(parent, localName, namespace) {
    if (!parent) return null;
    for (var node = parent.firstChild; node; node = node.nextSibling) {
        if (isElement(node, localName, namespace)) return node;
    }
    return null;
}

function childText(parent, localName, namespace) {
    return textContent(child(parent, localName, namespace));
}

// Some Qt responseXML implementations expose <yt:videoId> simply as
// "videoId". Prefer a verified namespace match; accept only known YouTube
// field names as compatibility fallbacks. Explicit foreign namespaces are
// never accepted, even if they happen to use the same local name.
function youtubeChild(parent, localName) {
    var verified = child(parent, localName, NS_YOUTUBE);
    if (verified) return verified;
    if (!parent) return null;
    for (var n = parent.firstChild; n; n = n.nextSibling) {
        if (n.nodeType !== 1) continue;
        var qualified = String(n.nodeName || "");
        if (qualified === localName) return n; // Qt may strip the prefix.
        if (qualified === "yt:" + localName &&
                !declaredNamespace(n, "yt")) return n;
    }
    return null;
}

function youtubeText(parent, localName) {
    return textContent(youtubeChild(parent, localName));
}

function videoIdFromAtomEntry(entry) {
    var atomId = childText(entry, "id", NS_ATOM);
    var match = /^yt:video:([A-Za-z0-9_-]{11})$/.exec(atomId.trim());
    return match ? match[1] : "";
}

function textContent(node) {
    if (!node) return "";
    var parts = [];
    function walk(n) {
        if (!n) return;
        if (n.nodeType === 3 || n.nodeType === 4) {
            parts.push(n.nodeValue || "");
            return;
        }
        for (var c = n.firstChild; c; c = c.nextSibling) walk(c);
    }
    walk(node);
    return parts.join("");
}

// YouTube's feed-level yt:channelId may omit the canonical UC prefix.
function normalizeChannelId(raw) {
    var value = String(raw || "").trim();
    if (/^UC[A-Za-z0-9_-]{22}$/.test(value)) return value;
    if (/^[A-Za-z0-9_-]{22}$/.test(value)) return "UC" + value;
    return "";
}

function safeThumbnailUrl(rawUrl) {
    var value = String(rawUrl || "").trim().replace(/&amp;/g, "&");
    // Fetch only thumbnails hosted by YouTube's known image servers, over TLS.
    if (/^https:\/\/(?:i\.ytimg\.com|img\.youtube\.com)\//i.test(value)) return value;
    return "";
}

function parseAtom(xmlDocument) {
    if (!xmlDocument || !isElement(xmlDocument.documentElement, "feed", NS_ATOM))
        throw new Error("YouTube returned an invalid Atom feed.");
    var feed = xmlDocument.documentElement;
    var rawFeedId = youtubeText(feed, "channelId");
    var channelId = normalizeChannelId(rawFeedId);
    if (rawFeedId && !channelId) throw new Error("Malformed feed channel ID.");
    var atomId = childText(feed, "id", NS_ATOM);
    var match = atomId.match(/^yt:channel:(UC[A-Za-z0-9_-]{22}|[A-Za-z0-9_-]{22})$/);
    if (match) {
        var fromAtomId = normalizeChannelId(match[1]);
        if (channelId && fromAtomId !== channelId) throw new Error("Conflicting feed channel IDs.");
        channelId = fromAtomId;
    }
    var channelName = childText(child(feed, "author", NS_ATOM), "name", NS_ATOM) ||
                      childText(feed, "title", NS_ATOM);
    var entries = [];
    var rawEntryCount = 0;
    var diagnostics = { videoTagIds: 0, atomFallbackIds: 0, missingIds: 0, invalidIds: 0,
                        conflictingIds: 0, strippedPrefixFields: 0, firstEntryFields: "" };
    for (var n = feed.firstChild; n; n = n.nextSibling) {
        if (!isElement(n, "entry", NS_ATOM)) continue;
        rawEntryCount++;
        // Node names only, with no text or attributes: useful for diagnosing
        // an unexpected Qt DOM layout without recording video content.
        if (rawEntryCount === 1) {
            var names = [];
            for (var field = n.firstChild; field && names.length < 20; field = field.nextSibling) {
                if (field.nodeType === 1) names.push(String(field.nodeName || "").slice(0, 40));
            }
            diagnostics.firstEntryFields = names.join(",");
        }
        var rawEntryId = youtubeText(n, "channelId");
        if (rawEntryId) {
            var entryId = normalizeChannelId(rawEntryId);
            if (!entryId) throw new Error("Malformed video channel ID in feed.");
            if (channelId && entryId !== channelId)
                throw new Error("Video belongs to a different channel than the feed.");
            channelId = entryId;
        }
        var ytVideoNode = youtubeChild(n, "videoId");
        var ytVideoId = textContent(ytVideoNode).trim();
        var atomVideoId = videoIdFromAtomEntry(n);
        var ytValid = /^[A-Za-z0-9_-]{11}$/.test(ytVideoId);
        // A mismatch means the feed has contradictory identity information.
        // Ignore that entire response rather than misattribute the video.
        if (ytValid && atomVideoId && ytVideoId !== atomVideoId) {
            diagnostics.conflictingIds++;
            throw new Error("Conflicting video identifiers in Atom entry.");
        }
        var videoId = ytValid ? ytVideoId : atomVideoId;
        if (!videoId) {
            if (ytVideoId) diagnostics.invalidIds++;
            else diagnostics.missingIds++;
            continue;
        }
        if (ytValid) diagnostics.videoTagIds++;
        else diagnostics.atomFallbackIds++;
        if (ytVideoNode && String(ytVideoNode.nodeName || "") === "videoId")
            diagnostics.strippedPrefixFields++;
        var published = Date.parse(childText(n, "published", NS_ATOM));
        var updated = Date.parse(childText(n, "updated", NS_ATOM));
        var mediaGroup = child(n, "group", NS_MEDIA);
        var feedThumbnail = child(mediaGroup, "thumbnail", NS_MEDIA);
        var thumbnail = safeThumbnailUrl(attribute(feedThumbnail, "url")) ||
                        "https://i.ytimg.com/vi/" + videoId + "/mqdefault.jpg";
        entries.push({
            id: videoId,
            title: childText(n, "title", NS_ATOM) || "Untitled video",
            channelName: childText(child(n, "author", NS_ATOM), "name", NS_ATOM) || channelName,
            publishedMs: isNaN(published) ? 0 : published,
            updatedMs: isNaN(updated) ? 0 : updated,
            thumbnail: thumbnail,
            url: "https://www.youtube.com/watch?v=" + videoId
        });
    }
    if (!channelId) throw new Error("Feed did not provide a verifiable channel ID.");
    return {channelId: channelId, channelName: channelName, entries: entries, rawEntryCount: rawEntryCount, diagnostics: diagnostics};
}
