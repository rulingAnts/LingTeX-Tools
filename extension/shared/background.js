/**
 * background.js — LingTeX Tools browser extension
 *
 * Minimal background service worker. Forwards the registered keyboard command
 * to the active tab's content script as a fallback for pages that might
 * suppress the keydown listener.
 */

chrome.commands.onCommand.addListener(function (command) {
    if (command !== 'smart-paste') return;
    chrome.tabs.query({ active: true, currentWindow: true }, function (tabs) {
        if (tabs[0]) {
            chrome.tabs.sendMessage(tabs[0].id, { type: 'SMART_PASTE' });
        }
    });
});
