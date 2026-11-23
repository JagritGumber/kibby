// Structural additions that bring Dolphin's window to Jagrit's mock: a title
// row with window buttons, a tool cluster beside the path bar, and a view-mode
// switch in the status bar. Every added button mirrors one of Dolphin's own
// actions; nothing here changes what Dolphin does.
#pragma once

class QWidget;

namespace DolphinLayout
{
// Dynamic properties the style reads to paint the widgets this module adds.
inline constexpr char FlatButton[] = "_caelestia_flat"; // window buttons: "minimize", "maximize" or "close"; drawn by the style
inline constexpr char Segment[] = "_caelestia_segment"; // "choice", "toggle" or "plain"
inline constexpr char SegmentGroup[] = "_caelestia_segment_group"; // filled pill behind segments
// The tool cluster beside the path bar; the style gives it no padding of its own.
inline constexpr char PathTools[] = "caelestiaPathTools";

// Call from QStyle::polish(QWidget *) inside Dolphin. Safe to call repeatedly.
void attach(QWidget *widget);
}
