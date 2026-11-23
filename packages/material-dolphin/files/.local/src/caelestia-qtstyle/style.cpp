// Caelestia Qt style: Darkly underneath, with Dolphin's toolbar, path bar,
// Places sidebar, file grid and status bar repainted in the Material shapes of
// the Caelestia shell.
//
// Every colour comes from the live QPalette, which the KDE platform theme fills
// from the Caelestia colour scheme. When the wallpaper changes, Qt rebuilds the
// palette, calls polish(QPalette&) again, and running windows repaint.
//
// Hooks are keyed on Dolphin's class names (read from Dolphin 26.08 / KIO 6.31).
// It is the session's widget style (kdeglobals [KDE] widgetStyle=caelestia, with
// ~/.local/lib/qt6/plugins on QT_PLUGIN_PATH), so Dolphin looks the same however
// it is started. KDE's file dialog (KFileWidget) gets the same Material layer
// where it is the whole app: the desktop portal's file picker, which browsers
// and Electron apps open, and kdialog. Every other Qt app gets plain Darkly.

#include "dolphinlayout.h"

#include <QAbstractItemView>
#include <QAbstractScrollArea>
#include <QApplication>
#include <QComboBox>
#include <QDockWidget>
#include <QEvent>
#include <QFileInfo>
#include <QGraphicsScene>
#include <QGraphicsView>
#include <QMainWindow>
#include <QPainter>
#include <QPainterPath>
#include <QPushButton>
#include <QProxyStyle>
#include <QSlider>
#include <QStyleFactory>
#include <QStyleOption>
#include <QStylePlugin>
#include <QToolBar>
#include <QToolButton>

#include <algorithm>

namespace {

// Sizes measured from Jagrit's mock, scaled to his 1846x1056 Dolphin window.
constexpr int kToolButtonSize = 50;
// Toolbar inset: keeps the nav buttons off Hyprland's rounded window corner.
constexpr int kEdgeInset = 12;
// The sidebar card fills the Places dock. Rows live in a viewport inset from the
// card, so the selection pill sits 24px in from the left and 8px from the right.
constexpr int kPlacesMinWidth = 290;
constexpr int kPlacesRowHeight = 50;
constexpr int kPlacesInsetLeft = 24;
constexpr int kPlacesInsetTop = 8;
constexpr int kPlacesInsetRight = 8;
constexpr int kPlacesInsetBottom = 12;
// KIO draws a Places icon 4px from the row edge; shift icon and text right so
// the icon sits ~20px inside the pill.
constexpr int kPlacesIndent = 7;
// The whole gap between sidebar and content is the dock's resize handle.
constexpr int kDockGutter = 16;
constexpr int kStatusBarHeight = 76;
constexpr int kStatusBarGap = 10;
// The file dialog uses Dolphin's shapes at dialog scale: its window is about a
// third of Dolphin's, and its toolbar holds a dozen buttons instead of three.
constexpr int kDialogButtonSize = 36;
constexpr int kDialogFieldHeight = 40;
// Places rows match the file list beside them (32px in the detail view).
constexpr int kDialogPlacesRowHeight = 32;
constexpr int kDialogPlacesInset = 8;
constexpr int kDialogEdge = 8;

// KStyleExtensions asks for custom elements through this hint, with the
// element's name temporarily set as the widget's objectName (kwidgetsaddons).
constexpr auto SH_KCustomStyleElement = static_cast<QStyle::StyleHint>(0xff000001);
constexpr auto CE_CapacityBar = static_cast<QStyle::ControlElement>(QStyle::CE_CustomBase + 0x100);

QString processName()
{
    return QFileInfo(QCoreApplication::applicationFilePath()).fileName();
}

// Processes whose file browsing gets the Material layer. The portal and
// kdialog exist to show dialogs, so their app-wide palette is safe to change.
bool isMaterialProcess(const QString &name)
{
    return name == QLatin1String("dolphin") || name == QLatin1String("xdg-desktop-portal-kde") || name == QLatin1String("kdialog");
}

const QWidget *ancestor(const QWidget *widget, const char *className, int depth)
{
    for (; widget != nullptr && depth >= 0; widget = widget->parentWidget(), --depth) {
        if (widget->inherits(className)) {
            return widget;
        }
    }
    return nullptr;
}

// Buttons in Dolphin's toolbar and in the tool cluster beside the path bar.
bool isToolBarButton(const QWidget *widget)
{
    return qobject_cast<const QToolButton *>(widget) != nullptr && qobject_cast<const QToolBar *>(widget->parentWidget()) != nullptr;
}

bool inFileDialog(const QWidget *widget)
{
    return ancestor(widget, "KFileWidget", 8) != nullptr;
}

// The file list in the dialog: detail, compact and icon views of KDirOperator.
bool isDirView(const QWidget *widget)
{
    return qobject_cast<const QAbstractItemView *>(widget) != nullptr && ancestor(widget, "KDirOperator", 3) != nullptr;
}

// The path bar while it is an editable text field (Dolphin and the dialog).
bool isPathCombo(const QWidget *widget)
{
    return widget != nullptr && widget->inherits("KUrlComboBox") && widget->parentWidget() != nullptr
        && widget->parentWidget()->inherits("KUrlNavigator");
}

// The dialog's Name and File type boxes.
bool isDialogField(const QWidget *widget)
{
    return widget != nullptr && (widget->inherits("KUrlComboBox") || widget->inherits("KFileFilterCombo")) && !isPathCombo(widget)
        && inFileDialog(widget);
}

bool isStyledCombo(const QWidget *widget)
{
    return isPathCombo(widget) || isDialogField(widget);
}

bool isSegment(const QWidget *widget)
{
    return widget != nullptr && widget->property(DolphinLayout::Segment).isValid();
}

QColor mix(const QColor &a, const QColor &b, qreal t)
{
    return QColor::fromRgbF(a.redF() + (b.redF() - a.redF()) * t,
                            a.greenF() + (b.greenF() - a.greenF()) * t,
                            a.blueF() + (b.blueF() - a.blueF()) * t,
                            a.alphaF() + (b.alphaF() - a.alphaF()) * t);
}

QColor withAlpha(QColor colour, qreal alpha)
{
    colour.setAlphaF(alpha);
    return colour;
}

QPalette::ColorGroup groupOf(const QStyleOption *option)
{
    if (!option->state.testFlag(QStyle::State_Enabled)) {
        return QPalette::Disabled;
    }
    return option->state.testFlag(QStyle::State_Active) ? QPalette::Active : QPalette::Inactive;
}

void fillRounded(QPainter *painter, const QRectF &rect, qreal radius, const QColor &fill, const QColor &border = QColor(), qreal borderWidth = 1.0)
{
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing, true);
    QRectF shape = rect;
    if (border.isValid() && border.alpha() > 0) {
        const qreal inset = borderWidth / 2.0;
        shape = rect.adjusted(inset, inset, -inset, -inset);
        painter->setPen(QPen(border, borderWidth));
    } else {
        painter->setPen(Qt::NoPen);
    }
    painter->setBrush(fill);
    radius = std::min(radius, std::min(shape.width(), shape.height()) / 2.0);
    painter->drawRoundedRect(shape, radius, radius);
    painter->restore();
}

void fillStadium(QPainter *painter, const QRectF &rect, const QColor &fill, const QColor &border = QColor())
{
    fillRounded(painter, rect, std::min(rect.width(), rect.height()) / 2.0, fill, border);
}

QIcon tinted(const QIcon &icon, const QSize &size, qreal dpr, const QColor &colour)
{
    QPixmap pixmap = icon.pixmap(size, dpr, QIcon::Normal, QIcon::On);
    if (pixmap.isNull()) {
        return icon;
    }
    QPainter painter(&pixmap);
    painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
    painter.fillRect(pixmap.rect(), colour);
    painter.end();
    return QIcon(pixmap);
}

bool isFileGrid(const QWidget *widget)
{
    return qobject_cast<const QGraphicsView *>(widget) != nullptr && widget->parentWidget() != nullptr
        && widget->parentWidget()->inherits("KItemListContainer");
}

// Dolphin draws a selected file's label in HighlightedText. The grid keeps the
// mock's subtle tint rather than a primary fill, so its scene keeps light label
// text instead of onPrimary. KItemListView takes its palette from the scene.
void keepGridLabelsLight(QGraphicsView *view)
{
    QGraphicsScene *scene = view->scene();
    if (scene == nullptr) {
        return;
    }
    QPalette palette = scene->palette();
    bool changed = false;
    for (const auto group : {QPalette::Active, QPalette::Inactive, QPalette::Disabled}) {
        const QColor text = palette.color(group, QPalette::Text);
        if (palette.color(group, QPalette::HighlightedText) != text) {
            palette.setColor(group, QPalette::HighlightedText, text);
            changed = true;
        }
    }
    if (changed) {
        scene->setPalette(palette);
    }
}

// The dialog's file list selects with the same tint as Dolphin's grid, so its
// selected labels keep the Text colour instead of onPrimary.
void keepLabelsLight(QWidget *view)
{
    QPalette palette = view->palette();
    bool changed = false;
    for (const auto group : {QPalette::Active, QPalette::Inactive, QPalette::Disabled}) {
        const QColor text = QApplication::palette(view).color(group, QPalette::Text);
        if (palette.color(group, QPalette::HighlightedText) != text) {
            palette.setColor(group, QPalette::HighlightedText, text);
            changed = true;
        }
    }
    if (changed) {
        view->setPalette(palette);
    }
}

// QAbstractScrollArea::setViewportMargins is protected. A pointer to member
// taken inside a subclass may be applied to any QAbstractScrollArea.
struct ScrollAreaAccess : QAbstractScrollArea {
    static void setMargins(QAbstractScrollArea *area, const QMargins &margins)
    {
        void (QAbstractScrollArea::*setter)(const QMargins &) = &ScrollAreaAccess::setViewportMargins;
        (area->*setter)(margins);
    }
};

} // namespace

class CaelestiaStyle final : public QProxyStyle
{
    Q_OBJECT
    // KCapacityBar only asks for CE_CapacityBar when the outermost style says so;
    // without this it falls back to Window.darker() gradients, a black slab here.
    Q_CLASSINFO("X-KDE-CustomElements", "true")

public:
    CaelestiaStyle()
        : QProxyStyle(createBase())
        , m_dolphin(processName() == QLatin1String("dolphin"))
        , m_material(isMaterialProcess(processName()))
    {
    }

    using QProxyStyle::polish;
    using QProxyStyle::unpolish;

    void polish(QPalette &palette) override
    {
        QProxyStyle::polish(palette);
        if (m_material) {
            applyMaterialRoles(palette);
        }
    }

    // Startup palettes come through polish(QPalette&), but plasma-integration
    // applies a wallpaper change with an explicit QApplication::setPalette(),
    // which Qt never polishes. Re-apply the roles after each such change.
    void reapplyMaterialRoles()
    {
        m_paletteQueued = false;
        QPalette palette = QApplication::palette();
        if (palette == m_ownPalette || hasMaterialRoles(palette)) {
            return;
        }
        applyMaterialRoles(palette);
        m_ownPalette = palette;
        QApplication::setPalette(palette);
        // Darkly pins a palette copy on toolbars after polish; drop it so the
        // buttons and path bar take the new colours too.
        const auto widgets = QApplication::allWidgets();
        for (QWidget *widget : widgets) {
            if (widget->inherits("KToolBar") && widget->testAttribute(Qt::WA_SetPalette)) {
                widget->setPalette(QPalette());
            } else if (isFileGrid(widget)) {
                keepGridLabelsLight(static_cast<QGraphicsView *>(widget));
            } else if (isDirView(widget)) {
                keepLabelsLight(widget);
            }
        }
    }

    // Dolphin re-sets the already polished palette explicitly at startup, so
    // recognise our own output: raw KDE palettes have Base != Window and a grey
    // Inactive selection.
    static bool hasMaterialRoles(const QPalette &palette)
    {
        const QColor highlight = palette.color(QPalette::Active, QPalette::Highlight);
        return palette.color(QPalette::Active, QPalette::Base) == palette.color(QPalette::Active, QPalette::Window)
            && palette.color(QPalette::Active, QPalette::Accent) == highlight && palette.color(QPalette::Inactive, QPalette::Highlight) == highlight;
    }

    static void applyMaterialRoles(QPalette &palette)
    {
        if (hasMaterialRoles(palette)) {
            return;
        }
        // Selection is the shell's pair: primary with onPrimary on top, the same
        // colours as Caelestia's active workspace pill. KDE greys selection in
        // unfocused windows; the shell never does, so Inactive copies Active.
        const QColor primary = palette.color(QPalette::Active, QPalette::Highlight);
        const QColor onPrimary = palette.color(QPalette::Active, QPalette::HighlightedText);
        for (const auto group : {QPalette::Active, QPalette::Inactive, QPalette::Disabled}) {
            const QColor text = palette.color(group, QPalette::Text);
            if (group != QPalette::Disabled) {
                palette.setColor(group, QPalette::Highlight, primary);
                palette.setColor(group, QPalette::HighlightedText, onPrimary);
            }
            palette.setColor(group, QPalette::Accent, palette.color(group, QPalette::Highlight));
            // Content sits on the window colour (surfaceContainer); only cards are lighter.
            const QColor window = palette.color(group, QPalette::Window);
            palette.setColor(group, QPalette::Base, window);
            palette.setColor(group, QPalette::AlternateBase, mix(window, text, 0.035));
        }
    }

    int styleHint(StyleHint hint, const QStyleOption *option, const QWidget *widget, QStyleHintReturn *returnData) const override
    {
        if (m_material && hint == SH_KCustomStyleElement && widget != nullptr && widget->objectName() == QLatin1String("CE_CapacityBar")) {
            return CE_CapacityBar;
        }
        return QProxyStyle::styleHint(hint, option, widget, returnData);
    }

    void drawControl(ControlElement element, const QStyleOption *option, QPainter *painter, const QWidget *widget) const override
    {
        if (m_material && element == CE_CapacityBar) {
            if (const auto *bar = qstyleoption_cast<const QStyleOptionProgressBar *>(option)) {
                paintCapacityBar(bar, painter);
            }
            return;
        }
        // Dolphin draws a 1px rule under the path bar once it leaves the
        // toolbar; the mock has none.
        if (m_dolphin && element == CE_ShapedFrame && widget != nullptr && widget->parentWidget() != nullptr
            && widget->parentWidget()->inherits("DolphinTabPage")) {
            if (const auto *frame = qstyleoption_cast<const QStyleOptionFrame *>(option); frame != nullptr && frame->frameShape == QFrame::HLine) {
                return;
            }
        }
        if (m_material && element == CE_ShapedFrame && inFileDialog(widget)) {
            // The dialog rules off its path bar and file list; Material separates
            // them with space instead.
            if (const auto *frame = qstyleoption_cast<const QStyleOptionFrame *>(option); frame != nullptr && frame->frameShape == QFrame::HLine) {
                return;
            }
        }
        if (m_material && element == CE_PushButton && inFileDialog(widget)) {
            if (const auto *button = qstyleoption_cast<const QStyleOptionButton *>(option)) {
                paintPushButton(button, painter, widget);
                return;
            }
        }
        QProxyStyle::drawControl(element, option, painter, widget);
    }

    void polish(QWidget *widget) override
    {
        QProxyStyle::polish(widget);
        if (!m_material) {
            return;
        }
        const bool dialog = inFileDialog(widget);
        if (widget->inherits("KToolBar")) {
            widget->installEventFilter(this);
        } else if (widget->inherits("DolphinDockWidget") && widget->objectName() == QLatin1String("placesDock")) {
            widget->setMinimumWidth(kPlacesMinWidth);
            // Darkly pads docks by 5/2/5/2; that dead strip hid the resize handle.
            widget->setContentsMargins(0, 0, 0, 0);
        } else if (dialog && qobject_cast<QDockWidget *>(widget) != nullptr) {
            // The dialog's Places dock: the card floats a little off the window edge.
            widget->setContentsMargins(kDialogEdge, kDialogEdge, 2, kDialogEdge);
        } else if (widget->inherits("KFilePlacesView")) {
            auto *view = static_cast<QAbstractScrollArea *>(widget);
            ScrollAreaAccess::setMargins(view,
                                         dialog ? QMargins(kDialogPlacesInset, kDialogPlacesInset, kDialogPlacesInset, kDialogPlacesInset)
                                                : QMargins(kPlacesInsetLeft, kPlacesInsetTop, kPlacesInsetRight, kPlacesInsetBottom));
            view->viewport()->setAutoFillBackground(false);
            // The card is painted on the view itself, behind the inset viewport.
            view->installEventFilter(this);
        } else if (isFileGrid(widget)) {
            keepGridLabelsLight(static_cast<QGraphicsView *>(widget));
        } else if (isDirView(widget)) {
            // The list sits on the window like Dolphin's view, without a frame.
            static_cast<QFrame *>(static_cast<QAbstractScrollArea *>(widget))->setFrameShape(QFrame::NoFrame);
            keepLabelsLight(widget);
        } else if (widget->property(DolphinLayout::SegmentGroup).toBool()) {
            widget->installEventFilter(this);
        } else if (widget->inherits("KDEPrivate::KUrlNavigatorDropDownButton")) {
            // Its arrow becomes the mock's folder icon; give the icon room.
            widget->setMinimumWidth(30);
        } else if (widget->inherits("KUrlNavigator")) {
            // KIO fixes the navigator to its combo box height (37px) so mode
            // switches never shift the layout; keep it fixed, at the button size.
            widget->setFixedHeight(dialog ? kDialogFieldHeight : kToolButtonSize);
        } else if (widget->inherits("DolphinStatusBar") && !widget->property("_caelestia_polished").toBool()) {
            widget->setProperty("_caelestia_polished", true);
            const auto children = widget->findChildren<QWidget *>();
            for (QWidget *child : children) {
                if (child->inherits("KSqueezedTextLabel")) {
                    child->parentWidget()->setContentsMargins(18, 0, 28, 0);
                    break;
                }
            }
            // The bar is as tall as its space-info row (preferredHeight()), so
            // grow that row to give the pill room around the text.
            for (QWidget *child : children) {
                if (child->inherits("StatusBarSpaceInfo")) {
                    const int height = std::max(child->minimumHeight(), kStatusBarHeight);
                    child->setFixedHeight(height);
                    if (widget->maximumHeight() > 0 && widget->maximumHeight() < QWIDGETSIZE_MAX) {
                        widget->setMaximumHeight(height);
                    }
                    break;
                }
            }
        }
        if (m_dolphin) {
            DolphinLayout::attach(widget);
        }
    }

    void unpolish(QWidget *widget) override
    {
        if (m_material && (widget->inherits("KFilePlacesView") || widget->inherits("KToolBar") || widget->property(DolphinLayout::SegmentGroup).toBool())) {
            widget->removeEventFilter(this);
        }
        QProxyStyle::unpolish(widget);
    }

    bool eventFilter(QObject *object, QEvent *event) override
    {
        // An app-wide palette change reaches child widgets as PaletteChange.
        const bool paletteEvent = event->type() == QEvent::PaletteChange || event->type() == QEvent::ApplicationPaletteChange;
        if (paletteEvent && !m_paletteQueued) {
            m_paletteQueued = true;
            QMetaObject::invokeMethod(this, &CaelestiaStyle::reapplyMaterialRoles, Qt::QueuedConnection);
        }
        if (event->type() == QEvent::Paint && object->inherits("KFilePlacesView")) {
            auto *view = static_cast<QWidget *>(object);
            QPainter painter(view);
            const QPalette &palette = view->palette();
            fillRounded(&painter, view->rect(), 18, mix(palette.color(QPalette::Window), palette.color(QPalette::WindowText), 0.06));
        } else if (event->type() == QEvent::Paint && object->property(DolphinLayout::SegmentGroup).toBool()) {
            auto *group = static_cast<QWidget *>(object);
            QPainter painter(group);
            const QPalette &palette = group->palette();
            fillStadium(&painter, group->rect(), mix(palette.color(QPalette::Window), palette.color(QPalette::WindowText), 0.09));
        }
        return QProxyStyle::eventFilter(object, event);
    }

    void drawPrimitive(PrimitiveElement element, const QStyleOption *option, QPainter *painter, const QWidget *widget) const override
    {
        if (m_material) {
            switch (element) {
            case PE_PanelItemViewItem:
                if (const auto *item = qstyleoption_cast<const QStyleOptionViewItem *>(option)) {
                    // KIO's Places delegate passes no widget; only option.widget says where it came from.
                    if (widget == nullptr && item->widget != nullptr && item->widget->inherits("KFilePlacesView")) {
                        paintPlacesRow(item, painter);
                        return;
                    }
                    if (ancestor(widget, "KItemListContainer", 3) != nullptr) {
                        paintFileItem(item, painter);
                        return;
                    }
                    if (isDirView(widget != nullptr ? widget : item->widget)) {
                        paintDirItem(item, painter);
                        return;
                    }
                }
                break;
            case PE_FrameFocusRect:
                if (ancestor(widget, "KItemListContainer", 3) != nullptr || isDirView(widget)) {
                    return;
                }
                break;
            case PE_FrameLineEdit:
                if (widget != nullptr && widget->inherits("KUrlNavigator")) {
                    paintField(option, painter, true);
                    return;
                }
                [[fallthrough]];
            case PE_PanelLineEdit:
                // The text box inside a styled field: the field already painted it.
                if (widget != nullptr && isStyledCombo(widget->parentWidget())) {
                    return;
                }
                // The path bar asks only for this panel. Darkly filled the
                // whole widget rect with it and then drew the frame (our pill)
                // on top, so square corners showed behind the pill's round
                // ends. Draw the pill here, alone.
                if (widget != nullptr && widget->inherits("KUrlNavigator")) {
                    paintField(option, painter, true);
                    return;
                }
                break;
            case PE_IndicatorToolBarSeparator:
                // Space alone separates the dialog's button groups.
                if (inFileDialog(widget)) {
                    return;
                }
                break;
            case PE_IndicatorArrowRight:
            case PE_IndicatorArrowLeft:
                // The path bar's leading drop-down (parent folders) shows the
                // mock's folder icon instead of an arrow; its menu still works.
                if (widget != nullptr && widget->inherits("KDEPrivate::KUrlNavigatorDropDownButton")) {
                    const int size = 18;
                    const QRect target(widget->rect().center() - QPoint(size / 2 - 1, size / 2 - 1), QSize(size, size));
                    const QIcon icon = tinted(QIcon::fromTheme(QStringLiteral("folder-symbolic")),
                                              QSize(size, size),
                                              widget->devicePixelRatioF(),
                                              option->palette.color(QPalette::Text));
                    icon.paint(painter, target);
                    return;
                }
                break;
            case PE_PanelButtonCommand:
                if (widget != nullptr && widget->inherits("KDEPrivate::KUrlNavigatorButtonBase")) {
                    const QRectF rect = QRectF(option->rect).adjusted(1, 4, -1, -4);
                    fillStadium(painter, rect, withAlpha(option->palette.color(QPalette::Text), 0.10));
                    return;
                }
                break;
            case PE_PanelStatusBar:
                if (widget != nullptr && widget->inherits("DolphinStatusBar")) {
                    const QPalette &palette = option->palette;
                    // The tab page already insets the content column by 6px.
                    const QRectF rect = QRectF(option->rect).adjusted(0, kStatusBarGap, -20, -kStatusBarGap);
                    fillStadium(painter,
                                rect,
                                mix(palette.color(QPalette::Window), palette.color(QPalette::WindowText), 0.08),
                                withAlpha(palette.color(QPalette::WindowText), 0.14));
                    return;
                }
                break;
            case PE_IndicatorDockWidgetResizeHandle:
                // The separator spans the whole gutter between sidebar and
                // content; show a slim grip only while it is under the cursor.
                if (widget != nullptr && widget->inherits("DolphinMainWindow")) {
                    if (option->state.testFlag(State_MouseOver)) {
                        const QRectF rect = option->rect;
                        const bool tall = rect.height() >= rect.width();
                        const QSizeF grip = tall ? QSizeF(4, 48) : QSizeF(48, 4);
                        fillStadium(painter,
                                    QRectF(rect.center() - QPointF(grip.width() / 2, grip.height() / 2), grip),
                                    withAlpha(option->palette.color(QPalette::WindowText), 0.35));
                    }
                    return;
                }
                break;
            default:
                break;
            }
        }
        QProxyStyle::drawPrimitive(element, option, painter, widget);
    }

    void drawComplexControl(ComplexControl control, const QStyleOptionComplex *option, QPainter *painter, const QWidget *widget) const override
    {
        if (m_material) {
            if (control == CC_ToolButton && (isToolBarButton(widget) || isSegment(widget))) {
                if (const auto *button = qstyleoption_cast<const QStyleOptionToolButton *>(option)) {
                    isSegment(widget) ? paintSegment(button, painter, widget) : paintToolButton(button, painter, widget);
                    return;
                }
            }
            if (control == CC_ComboBox && isStyledCombo(widget)) {
                if (const auto *combo = qstyleoption_cast<const QStyleOptionComboBox *>(option)) {
                    paintField(combo, painter, isPathCombo(widget));
                    // Darkly fills an editable combo's frame with Base; leave it
                    // only the arrow to draw.
                    QStyleOptionComboBox flat = *combo;
                    flat.frame = false;
                    flat.subControls &= ~SC_ComboBoxFrame;
                    flat.state &= ~(State_HasFocus | State_MouseOver);
                    QProxyStyle::drawComplexControl(control, &flat, painter, widget);
                    return;
                }
            }
            const bool dialogSlider = inFileDialog(widget) && widget != nullptr && qobject_cast<const QToolBar *>(widget->parentWidget()) != nullptr;
            if (control == CC_Slider && (dialogSlider || ancestor(widget, "DolphinStatusBar", 4) != nullptr)) {
                if (const auto *slider = qstyleoption_cast<const QStyleOptionSlider *>(option)) {
                    paintSlider(slider, painter, widget);
                    return;
                }
            }
        }
        QProxyStyle::drawComplexControl(control, option, painter, widget);
    }

    QSize sizeFromContents(ContentsType type, const QStyleOption *option, const QSize &contents, const QWidget *widget) const override
    {
        QSize size = QProxyStyle::sizeFromContents(type, option, contents, widget);
        if (!m_material) {
            return size;
        }
        if (type == CT_PushButton && inFileDialog(widget)) {
            return QSize(std::max(size.width() + 12, 104), kDialogFieldHeight);
        }
        if (type == CT_ComboBox && isDialogField(widget)) {
            return QSize(size.width(), std::max(size.height(), kDialogFieldHeight));
        }
        if (type == CT_ToolButton && isSegment(widget)) {
            // 40px segments: icon-only choices are a little wider, like the mock's pills.
            const auto *button = qstyleoption_cast<const QStyleOptionToolButton *>(option);
            const bool withText = button != nullptr && button->toolButtonStyle != Qt::ToolButtonIconOnly && !button->text.isEmpty();
            const bool choice = widget->property(DolphinLayout::Segment).toString() == QLatin1String("choice");
            return QSize(withText ? size.width() + 20 : (choice ? 56 : 40), 40);
        }
        if (type == CT_ToolButton && isToolBarButton(widget)) {
            const auto *button = qstyleoption_cast<const QStyleOptionToolButton *>(option);
            const bool iconOnly = button == nullptr || button->toolButtonStyle == Qt::ToolButtonIconOnly || button->text.isEmpty();
            const int height = inFileDialog(widget) ? kDialogButtonSize : std::max(size.height(), kToolButtonSize);
            return iconOnly && button != nullptr && !(button->features & QStyleOptionToolButton::MenuButtonPopup)
                ? QSize(height, height)
                : QSize(std::max(size.width() + 16, height), height);
        }
        if (type == CT_ItemViewItem) {
            const auto *item = qstyleoption_cast<const QStyleOptionViewItem *>(option);
            const QWidget *view = widget != nullptr ? widget : (item != nullptr ? item->widget : nullptr);
            if (view != nullptr && view->inherits("KFilePlacesView")) {
                size.setHeight(std::max(size.height(), inFileDialog(view) ? kDialogPlacesRowHeight : kPlacesRowHeight));
            }
        }
        return size;
    }

    int pixelMetric(PixelMetric metric, const QStyleOption *option, const QWidget *widget) const override
    {
        // Darkly's 1px dock separator was the only grab target, an invisible
        // line beside the sidebar. Make the whole gutter the handle. Qt asks in
        // QMainWindow's constructor, before the object is a DolphinMainWindow.
        if (m_dolphin && metric == PM_DockWidgetSeparatorExtent && qobject_cast<const QMainWindow *>(widget) != nullptr) {
            return kDockGutter;
        }
        // QToolBar reads these in its own constructor, before the object is a
        // KToolBar, so match the Qt base class.
        if (m_material && qobject_cast<const QToolBar *>(widget) != nullptr && inFileDialog(widget)) {
            switch (metric) {
            case PM_ToolBarItemSpacing:
                return 4;
            case PM_ToolBarItemMargin:
                return kDialogEdge - 2;
            case PM_ToolBarFrameWidth:
                return 2;
            case PM_ToolBarSeparatorExtent:
                return 12;
            default:
                break;
            }
        }
        if (m_dolphin && widget != nullptr && widget->objectName() == QLatin1String(DolphinLayout::PathTools)) {
            switch (metric) {
            case PM_ToolBarItemMargin:
            case PM_ToolBarFrameWidth:
                return 0;
            case PM_ToolBarItemSpacing:
                return 6;
            default:
                break;
            }
        }
        if (m_dolphin && qobject_cast<const QToolBar *>(widget) != nullptr) {
            switch (metric) {
            case PM_ToolBarItemSpacing:
                return 6;
            case PM_ToolBarItemMargin:
                return kEdgeInset - 2;
            case PM_ToolBarFrameWidth:
                return 2;
            default:
                break;
            }
        }
        return QProxyStyle::pixelMetric(metric, option, widget);
    }

private:
    static QStyle *createBase()
    {
        if (QStyle *darkly = QStyleFactory::create(QStringLiteral("Darkly"))) {
            return darkly;
        }
        return QStyleFactory::create(QStringLiteral("Fusion"));
    }

    static void paintPlacesRow(const QStyleOptionViewItem *item, QPainter *painter)
    {
        const QPalette &palette = item->palette;
        const QPalette::ColorGroup group = groupOf(item);
        // The viewport is already inset from the card, so the pill fills the row.
        const QRectF pill = QRectF(item->rect).adjusted(0, 1, 0, -1);
        if (item->state.testFlag(State_Selected)) {
            // The shell's active pill: primary, with onPrimary label and icon.
            // Qt clears State_Active whenever the Places view lacks keyboard
            // focus (almost always), and KIO then draws a light label. KIO
            // passes its own non-const local copy of the option and reads
            // State_Active only after this hook, so mark the row active here.
            const_cast<QStyleOptionViewItem *>(item)->state |= State_Active;
            fillStadium(painter, pill, palette.color(group, QPalette::Highlight));
        } else if (item->state.testFlag(State_MouseOver)) {
            fillStadium(painter, pill, withAlpha(palette.color(group, QPalette::WindowText), 0.08));
        }
        // The delegate wraps paint() in save()/restore(), so this shift moves
        // its icon, label and capacity bar and ends with the row.
        painter->translate(kPlacesIndent, 0);
    }

    static void paintFileItem(const QStyleOptionViewItem *item, QPainter *painter)
    {
        const bool selected = item->state.testFlag(State_Selected);
        const bool hovered = item->state.testFlag(State_MouseOver);
        if (!selected && !hovered) {
            return;
        }
        const QPalette &palette = item->palette;
        const QPalette::ColorGroup group = groupOf(item);
        const QColor accent = palette.color(group, QPalette::Accent);
        const QRectF rect = QRectF(item->rect).adjusted(1, 1, -1, -1);
        const bool tile = rect.height() >= 56 && rect.width() <= rect.height() * 2.6;
        const qreal radius = tile ? 16 : std::min<qreal>(10, rect.height() / 2);

        if (!selected) {
            fillRounded(painter, rect, radius, withAlpha(palette.color(group, QPalette::Text), 0.06));
            return;
        }
        fillRounded(painter, rect, radius, withAlpha(accent, hovered ? 0.16 : 0.10), withAlpha(accent, 0.85), 1.5);
        if (!tile) {
            return;
        }

        const qreal diameter = std::clamp(rect.width() * 0.15, 18.0, 24.0);
        const QRectF badge(rect.right() - diameter - 7, rect.top() + 7, diameter, diameter);
        QPainterPath check;
        check.moveTo(badge.left() + diameter * 0.28, badge.top() + diameter * 0.53);
        check.lineTo(badge.left() + diameter * 0.44, badge.top() + diameter * 0.68);
        check.lineTo(badge.left() + diameter * 0.73, badge.top() + diameter * 0.36);

        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        painter->setPen(Qt::NoPen);
        painter->setBrush(accent);
        painter->drawEllipse(badge);
        painter->setBrush(Qt::NoBrush);
        painter->setPen(QPen(palette.color(group, QPalette::Base), diameter * 0.11, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        painter->drawPath(check);
        painter->restore();
    }

    static void paintCapacityBar(const QStyleOptionProgressBar *bar, QPainter *painter)
    {
        const QPalette &palette = bar->palette;
        const QColor text = palette.color(QPalette::WindowText);
        const qreal thickness = 6;
        const QRectF track(bar->rect.left(), bar->rect.center().y() - thickness / 2 + 0.5, bar->rect.width(), thickness);
        const qreal span = bar->maximum > bar->minimum ? qreal(bar->progress - bar->minimum) / (bar->maximum - bar->minimum) : 0;
        fillStadium(painter, track, withAlpha(text, 0.18));
        if (span > 0) {
            const QRectF filled(track.left(), track.top(), std::max(thickness, track.width() * std::min<qreal>(span, 1)), thickness);
            fillStadium(painter, filled, palette.color(QPalette::Accent));
        }
        if (bar->textVisible && !bar->text.isEmpty()) {
            painter->save();
            painter->setPen(text);
            painter->drawText(bar->rect, Qt::AlignCenter, bar->text);
            painter->restore();
        }
    }

    // The path bar is a pill; the dialog's Name and File type boxes are filled
    // fields with Material's 12px corners. Both outline in the accent on focus.
    static void paintField(const QStyleOption *option, QPainter *painter, bool pill)
    {
        const QPalette &palette = option->palette;
        const QColor window = palette.color(QPalette::Window);
        const QColor text = palette.color(QPalette::WindowText);
        const bool hovered = option->state.testFlag(State_MouseOver);
        const bool focused = option->state.testFlag(State_HasFocus);
        const QColor border = focused ? QApplication::palette().color(QPalette::Active, QPalette::Accent) : withAlpha(text, 0.12);
        const QRectF rect = QRectF(option->rect).adjusted(0, 1, 0, -1);
        fillRounded(painter, rect, pill ? rect.height() / 2 : 12, mix(window, text, hovered ? 0.09 : 0.06), border, focused ? 1.5 : 1.0);
    }

    // A file row in the dialog. Detail view paints one cell per column, so the
    // tint runs across the row and only its outer ends are rounded. Single
    // cells (icon and compact views) take Dolphin's item look.
    static void paintDirItem(const QStyleOptionViewItem *item, QPainter *painter)
    {
        const auto position = item->viewItemPosition;
        if (position == QStyleOptionViewItem::Invalid || position == QStyleOptionViewItem::OnlyOne) {
            paintFileItem(item, painter);
            return;
        }
        const bool selected = item->state.testFlag(State_Selected);
        const bool hovered = item->state.testFlag(State_MouseOver);
        if (!selected && !hovered) {
            return;
        }
        const QPalette &palette = item->palette;
        const QPalette::ColorGroup group = groupOf(item);
        const QColor fill = selected ? withAlpha(palette.color(group, QPalette::Accent), hovered ? 0.32 : 0.26)
                                     : withAlpha(palette.color(group, QPalette::Text), 0.06);
        const QRectF cell = QRectF(item->rect).adjusted(0, 1, 0, -1);
        const qreal radius = std::min<qreal>(10, cell.height() / 2);
        // Extend the shape past the cell's inner sides and clip, so only the
        // row's outer corners show rounding.
        QRectF shape = cell;
        if (position != QStyleOptionViewItem::Beginning) {
            shape.setLeft(shape.left() - radius * 2);
        }
        if (position != QStyleOptionViewItem::End) {
            shape.setRight(shape.right() + radius * 2);
        }
        painter->save();
        painter->setClipRect(cell);
        fillRounded(painter, shape, radius, fill);
        painter->restore();
    }

    // Open/Save is the primary action: a primary pill. Cancel is tonal.
    void paintPushButton(const QStyleOptionButton *button, QPainter *painter, const QWidget *widget) const
    {
        const QPalette &palette = button->palette;
        const QPalette app = QApplication::palette(widget);
        const QColor window = palette.color(QPalette::Window);
        const QColor text = palette.color(QPalette::ButtonText);
        const bool enabled = button->state.testFlag(State_Enabled);
        const bool pressed = button->state.testFlag(State_Sunken);
        const bool hovered = enabled && button->state.testFlag(State_MouseOver);
        const bool primary = button->features.testFlag(QStyleOptionButton::DefaultButton);

        QColor fill = mix(window, text, pressed ? 0.20 : hovered ? 0.14 : 0.09);
        QColor onFill = text;
        if (primary) {
            onFill = app.color(QPalette::Active, QPalette::HighlightedText);
            fill = mix(app.color(QPalette::Active, QPalette::Accent), onFill, pressed ? 0.16 : hovered ? 0.08 : 0.0);
        }
        if (!enabled) {
            fill = primary ? mix(window, text, 0.09) : withAlpha(fill, 0.6);
            onFill = withAlpha(text, 0.45);
        }
        fillStadium(painter, QRectF(button->rect).adjusted(1, 1, -1, -1), fill);

        QStyleOptionButton label = *button;
        label.state &= ~State_HasFocus;
        for (const auto group : {QPalette::Active, QPalette::Inactive, QPalette::Disabled}) {
            label.palette.setColor(group, QPalette::ButtonText, onFill);
        }
        if (!label.icon.isNull()) {
            label.icon = tinted(label.icon, label.iconSize, widget->devicePixelRatioF(), onFill);
        }
        QProxyStyle::drawControl(CE_PushButtonLabel, &label, painter, widget);
    }

    void paintToolButton(const QStyleOptionToolButton *button, QPainter *painter, const QWidget *widget) const
    {
        const QPalette &palette = button->palette;
        const QColor window = palette.color(QPalette::Window);
        const QColor text = palette.color(QPalette::ButtonText);
        const bool enabled = button->state.testFlag(State_Enabled);
        const bool checked = button->state.testFlag(State_On);
        const bool pressed = button->state.testFlag(State_Sunken);
        const bool hovered = enabled && button->state.testFlag(State_MouseOver);
        const bool iconOnly = button->toolButtonStyle == Qt::ToolButtonIconOnly || button->text.isEmpty();
        // Window buttons are bare glyphs in the mock; they only light up on hover.
        const QString glyph = widget->property(DolphinLayout::FlatButton).toString();
        const bool flat = !glyph.isEmpty();

        // Darkly pins KDE's raw palette on toolbars, whose unfocused Accent is
        // grey; take the accent from the application palette instead.
        const QPalette app = QApplication::palette(widget);
        QColor fill = mix(window, text, pressed ? 0.20 : hovered ? 0.14 : 0.09);
        if (checked) {
            fill = app.color(QPalette::Active, QPalette::Accent);
        }
        if (!enabled) {
            // Still a visible circle, so the nav row keeps its shape at Home.
            fill = withAlpha(fill, fill.alphaF() * 0.7);
        }

        QRectF shape = button->rect;
        if (iconOnly && !(button->features & QStyleOptionToolButton::MenuButtonPopup)) {
            const qreal side = std::min(shape.width(), shape.height()) - (flat ? 8 : 0);
            shape = QRectF(shape.center().x() - side / 2, shape.center().y() - side / 2, side, side);
        }
        if (!flat || hovered || pressed) {
            fillStadium(painter, shape, fill);
        }
        if (flat) {
            paintWindowGlyph(painter, QRectF(button->rect).center(), glyph, text);
            return;
        }
        drawLabel(button, painter, widget, checked ? app.color(QPalette::Active, QPalette::HighlightedText) : QColor());
    }

    // The mock's window buttons: a line, a rounded square and a cross.
    static void paintWindowGlyph(QPainter *painter, const QPointF &centre, const QString &glyph, const QColor &colour)
    {
        constexpr qreal half = 6;
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        painter->setPen(QPen(colour, 1.6, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        painter->setBrush(Qt::NoBrush);
        if (glyph == QLatin1String("minimize")) {
            painter->drawLine(centre - QPointF(half, 0), centre + QPointF(half, 0));
        } else if (glyph == QLatin1String("maximize")) {
            painter->drawRoundedRect(QRectF(centre - QPointF(half - 1, half - 1), QSizeF(2 * half - 2, 2 * half - 2)), 2.5, 2.5);
        } else {
            const qreal arm = half - 0.5;
            painter->drawLine(centre + QPointF(-arm, -arm), centre + QPointF(arm, arm));
            painter->drawLine(centre + QPointF(-arm, arm), centre + QPointF(arm, -arm));
        }
        painter->restore();
    }

    // Segments of the panel/Split pill and the status bar's view-mode switch.
    // A chosen view mode is a primary pill; an "on" toggle is a darker inset.
    void paintSegment(const QStyleOptionToolButton *button, QPainter *painter, const QWidget *widget) const
    {
        const QPalette &palette = button->palette;
        const QColor window = palette.color(QPalette::Window);
        const QColor text = palette.color(QPalette::ButtonText);
        const QString kind = widget->property(DolphinLayout::Segment).toString();
        const bool enabled = button->state.testFlag(State_Enabled);
        const bool checked = button->state.testFlag(State_On);
        const bool hovered = enabled && (button->state.testFlag(State_MouseOver) || button->state.testFlag(State_Sunken));
        const QPalette app = QApplication::palette(widget);

        QColor fill;
        QColor onFill;
        if (checked && kind == QLatin1String("choice")) {
            fill = app.color(QPalette::Active, QPalette::Accent);
            onFill = app.color(QPalette::Active, QPalette::HighlightedText);
        } else if (checked && kind == QLatin1String("toggle")) {
            fill = mix(window, text, hovered ? 0.24 : 0.18);
        } else if (hovered) {
            fill = mix(window, text, 0.16);
        }
        if (fill.isValid()) {
            fillStadium(painter, QRectF(button->rect).adjusted(0.5, 0.5, -0.5, -0.5), fill);
        }
        drawLabel(button, painter, widget, onFill);
    }

    // Darkly draws only the label for an auto-raised button at rest.
    void drawLabel(const QStyleOptionToolButton *button, QPainter *painter, const QWidget *widget, const QColor &onFill) const
    {
        QStyleOptionToolButton label = *button;
        label.state &= ~(State_MouseOver | State_Sunken | State_On | State_HasFocus);
        label.state |= State_AutoRaise;
        label.activeSubControls = SC_None;
        // Back/forward keep their history menu on long-press, without the arrow.
        if (!(label.features & QStyleOptionToolButton::MenuButtonPopup)) {
            label.features &= ~QStyleOptionToolButton::HasMenu;
        }
        if (onFill.isValid()) {
            label.icon = tinted(button->icon, button->iconSize, widget->devicePixelRatioF(), onFill);
            label.palette.setColor(QPalette::ButtonText, onFill);
            label.palette.setColor(QPalette::WindowText, onFill);
        }
        QProxyStyle::drawComplexControl(CC_ToolButton, &label, painter, widget);
    }

    void paintSlider(const QStyleOptionSlider *slider, QPainter *painter, const QWidget *widget) const
    {
        const QPalette &palette = slider->palette;
        const QColor accent = palette.color(QPalette::Accent);
        const QRectF groove = subControlRect(CC_Slider, slider, SC_SliderGroove, widget);
        const QRectF handle = subControlRect(CC_Slider, slider, SC_SliderHandle, widget);
        const qreal y = groove.center().y();
        const QRectF track(groove.left() + 2, y - 2, groove.width() - 4, 4);
        const QRectF filled(track.left(), track.top(), std::max<qreal>(0, handle.center().x() - track.left()), track.height());
        const qreal knob = 16;

        fillStadium(painter, track, withAlpha(palette.color(QPalette::WindowText), 0.18));
        fillStadium(painter, filled, accent);
        painter->save();
        painter->setRenderHint(QPainter::Antialiasing, true);
        painter->setPen(Qt::NoPen);
        painter->setBrush(accent);
        painter->drawEllipse(QRectF(handle.center().x() - knob / 2, y - knob / 2, knob, knob));
        painter->restore();
    }

    const bool m_dolphin;
    const bool m_material;
    bool m_paletteQueued = false;
    QPalette m_ownPalette;
};

class CaelestiaStylePlugin final : public QStylePlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QStyleFactoryInterface" FILE "caelestia.json")

public:
    QStyle *create(const QString &key) override
    {
        if (key.compare(QStringLiteral("caelestia"), Qt::CaseInsensitive) == 0) {
            return new CaelestiaStyle;
        }
        return nullptr;
    }
};

#include "style.moc"
