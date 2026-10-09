// TerminalBuffer.js - Virtual Terminal screen buffer and ANSI parser
.pragma library

var ANSI_COLORS = {
  0: "#1e1e2e",   // Black
  1: "#f38ba8",   // Red
  2: "#a6e3a1",   // Green
  3: "#f9e2af",   // Yellow
  4: "#89b4fa",   // Blue
  5: "#cba6f7",   // Magenta
  6: "#94e2d5",   // Cyan
  7: "#cdd6f4",   // White
  // Bright colors (8-15)
  8: "#585b70",   // Bright Black
  9: "#f38ba8",   // Bright Red
  10: "#a6e3a1",  // Bright Green
  11: "#f9e2af",  // Bright Yellow
  12: "#89b4fa",  // Bright Blue
  13: "#cba6f7",  // Bright Magenta
  14: "#94e2d5",  // Bright Cyan
  15: "#ffffff"   // Bright White
};

function createTerminal(options) {
  options = options || {};
  var maxLines = options.maxLines || 2000;
  var termCols = options.cols || 100;
  var termRows = options.rows || 30;

  var lines = [""];
  var cursorCol = 0;
  var currentFg = "";
  var currentBg = "";
  var isBold = false;
  var isItalic = false;
  var isUnderline = false;
  var title = "";

  function escapeHtml(text) {
    return text.replace(/&/g, "&amp;")
               .replace(/</g, "&lt;")
               .replace(/>/g, "&gt;")
               .replace(/"/g, "&quot;")
               .replace(/'/g, "&#039;");
  }

  function styleSpan(text) {
    if (!text) return "";
    var style = "";
    if (currentFg) style += "color:" + currentFg + ";";
    if (currentBg) style += "background-color:" + currentBg + ";";
    if (isBold) style += "font-weight:bold;";
    if (isItalic) style += "font-style:italic;";
    if (isUnderline) style += "text-decoration:underline;";

    var esc = escapeHtml(text);
    if (style) {
      return "<span style='" + style + "'>" + esc + "</span>";
    }
    return esc;
  }

  function processText(raw) {
    var i = 0;
    var len = raw.length;

    while (i < len) {
      var ch = raw.charAt(i);

      // Carriage return
      if (ch === '\r') {
        cursorCol = 0;
        i++;
        continue;
      }

      // Line feed
      if (ch === '\n') {
        lines.push("");
        cursorCol = 0;
        if (lines.length > maxLines) {
          lines.shift();
        }
        i++;
        continue;
      }

      // Backspace
      if (ch === '\b') {
        cursorCol = Math.max(0, cursorCol - 1);
        i++;
        continue;
      }

      // Tab
      if (ch === '\t') {
        var spaces = 8 - (cursorCol % 8);
        for (var s = 0; s < spaces; s++) {
          appendChar(" ");
        }
        i++;
        continue;
      }

      // Bell / non-printable
      if (ch.charCodeAt(0) < 32 && ch !== '\x1b') {
        i++;
        continue;
      }

      // Escape sequence
      if (ch === '\x1b') {
        if (i + 1 >= len) break;
        var next = raw.charAt(i + 1);

        // OSC sequence: \x1b] ... \x07 or \x1b\
        if (next === ']') {
          var oscEnd = raw.indexOf('\x07', i + 2);
          var oscEnd2 = raw.indexOf('\x1b\\', i + 2);
          var endIdx = -1;
          if (oscEnd !== -1 && oscEnd2 !== -1) endIdx = Math.min(oscEnd, oscEnd2);
          else if (oscEnd !== -1) endIdx = oscEnd;
          else if (oscEnd2 !== -1) endIdx = oscEnd2;

          if (endIdx !== -1) {
            var oscPayload = raw.substring(i + 2, endIdx);
            // Title setting: 0;title or 2;title
            if (oscPayload.indexOf("0;") === 0 || oscPayload.indexOf("2;") === 0) {
              title = oscPayload.substring(2);
            }
            i = (raw.charAt(endIdx) === '\x1b') ? endIdx + 2 : endIdx + 1;
            continue;
          } else {
            // Incomplete OSC, skip escape
            i += 2;
            continue;
          }
        }

        // CSI sequence: \x1b[ ...
        if (next === '[') {
          var j = i + 2;
          while (j < len && raw.charCodeAt(j) >= 0x20 && raw.charCodeAt(j) <= 0x3f) {
            j++;
          }
          if (j < len) {
            var cmd = raw.charAt(j);
            var params = raw.substring(i + 2, j);
            handleCsi(cmd, params);
            i = j + 1;
            continue;
          } else {
            i = len;
            continue;
          }
        }

        // Other escape: skip \x1b and next char
        i += 2;
        continue;
      }

      // Plain character
      appendChar(ch);
      i++;
    }
  }

  function handleCsi(cmd, params) {
    if (cmd === 'm') {
      // SGR Color / Style
      var codes = params ? params.split(';').map(function(c) { return parseInt(c, 10) || 0; }) : [0];
      for (var idx = 0; idx < codes.length; idx++) {
        var c = codes[idx];
        if (c === 0) {
          currentFg = "";
          currentBg = "";
          isBold = false;
          isItalic = false;
          isUnderline = false;
        } else if (c === 1) {
          isBold = true;
        } else if (c === 3) {
          isItalic = true;
        } else if (c === 4) {
          isUnderline = true;
        } else if (c === 22) {
          isBold = false;
        } else if (c === 23) {
          isItalic = false;
        } else if (c === 24) {
          isUnderline = false;
        } else if (c >= 30 && c <= 37) {
          currentFg = ANSI_COLORS[c - 30] || "";
        } else if (c === 39) {
          currentFg = "";
        } else if (c >= 40 && c <= 47) {
          currentBg = ANSI_COLORS[c - 40] || "";
        } else if (c === 49) {
          currentBg = "";
        } else if (c >= 90 && c <= 97) {
          currentFg = ANSI_COLORS[c - 90 + 8] || "";
        } else if (c >= 100 && c <= 107) {
          currentBg = ANSI_COLORS[c - 100 + 8] || "";
        } else if (c === 38 && codes[idx + 1] === 5) {
          // 256 colors
          var c256 = codes[idx + 2];
          if (c256 !== undefined && ANSI_COLORS[c256 % 16]) {
            currentFg = ANSI_COLORS[c256 % 16];
          }
          idx += 2;
        } else if (c === 38 && codes[idx + 1] === 2) {
          // 24-bit RGB truecolor
          var r = codes[idx + 2], g = codes[idx + 3], b = codes[idx + 4];
          if (r !== undefined && g !== undefined && b !== undefined) {
            currentFg = "rgb(" + r + "," + g + "," + b + ")";
          }
          idx += 4;
        }
      }
    } else if (cmd === 'K') {
      // Erase in line
      var currLine = lines[lines.length - 1] || "";
      // param 0 or empty: erase cursor to end
      if (!params || params === "0") {
        lines[lines.length - 1] = currLine.substring(0, cursorCol);
      } else if (params === "2") {
        lines[lines.length - 1] = "";
        cursorCol = 0;
      }
    } else if (cmd === 'J') {
      // Erase in display
      if (params === "2" || params === "3") {
        lines = [""];
        cursorCol = 0;
      }
    } else if (cmd === 'G') {
      // Move cursor to column
      var col = parseInt(params, 10) || 1;
      cursorCol = Math.max(0, col - 1);
    } else if (cmd === 'A') {
      // Cursor up
    } else if (cmd === 'B') {
      // Cursor down
    } else if (cmd === 'C') {
      // Cursor forward
      var fwd = parseInt(params, 10) || 1;
      cursorCol += fwd;
    } else if (cmd === 'D') {
      // Cursor backward
      var back = parseInt(params, 10) || 1;
      cursorCol = Math.max(0, cursorCol - back);
    }
  }

  function appendChar(ch) {
    var lineIdx = lines.length - 1;
    var line = lines[lineIdx] || "";
    var styled = styleSpan(ch);

    if (cursorCol >= line.length) {
      // Pad with spaces if cursorCol was moved forward
      while (line.length < cursorCol) {
        line += " ";
      }
      lines[lineIdx] = line + styled;
    } else {
      // Overwrite character at cursorCol
      lines[lineIdx] = line.substring(0, cursorCol) + styled + line.substring(cursorCol + 1);
    }
    cursorCol++;
  }

  return {
    write: function(data) {
      processText(data);
    },
    getLines: function() {
      return lines;
    },
    getLineCount: function() {
      return lines.length;
    },
    getTitle: function() {
      return title;
    },
    clear: function() {
      lines = [""];
      cursorCol = 0;
    }
  };
}
