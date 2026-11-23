#include "dolphinlayout.h"

#include <KActionCollection>
#include <KXmlGuiWindow>

#include <QAction>
#include <QActionEvent>
#include <QFont>
#include <QGridLayout>
#include <QHBoxLayout>
#include <QIcon>
#include <QLabel>
#include <QProcess>
#include <QToolBar>
#include <QToolButton>

#include <functional>

namespace
{
constexpr char Attached[] = "_caelestia_layout";
constexpr char TitleRowItem[] = "_caelestia_title_row";
constexpr int kTitlePixelSize = 24;

QAction *dolphinAction(const QWidget *widget, const char *name)
{
    // Dolphin's actions live in its KXMLGUI action collection, which is not a
    // QObject child of the window; only dock toggles are found by findChild.
    if (const auto *window = qobject_cast<const KXmlGuiWindow *>(widget->window())) {
        if (QAction *action = window->actionCollection()->action(QLatin1String(name))) {
            return action;
        }
    }
    return widget->window()->findChild<QAction *>(QLatin1String(name));
}

bool onHyprland()
{
    return qEnvironmentVariableIsSet("HYPRLAND_INSTANCE_SIGNATURE");
}

// Acts on the focused window, which is this one once its button is clicked.
void hyprDispatch(const QString &lua)
{
    QProcess::startDetached(QStringLiteral("hyprctl"), {QStringLiteral("dispatch"), lua});
}

QString titleFor(const QWidget *window)
{
    QString title = window->windowTitle();
    const int suffix = title.lastIndexOf(QStringLiteral(" — ")); // KMainWindow appends " — Dolphin"
    if (suffix > 0) {
        title.truncate(suffix);
    }
    return title;
}

QWidget *segmentGroup(QWidget *parent, bool filled)
{
    auto *group = new QWidget(parent);
    group->setProperty(DolphinLayout::SegmentGroup, filled);
    auto *layout = new QHBoxLayout(group);
    const int inset = filled ? 4 : 0;
    layout->setContentsMargins(inset, inset, inset, inset);
    layout->setSpacing(2);
    return group;
}

void addSegment(QWidget *group, QAction *action, const char *kind, Qt::ToolButtonStyle style)
{
    if (action == nullptr) {
        return;
    }
    auto *button = new QToolButton(group);
    button->setDefaultAction(action);
    button->setAutoRaise(true);
    button->setFocusPolicy(Qt::NoFocus);
    button->setToolButtonStyle(style);
    // Split is a menu action: click splits, press-and-hold opens its menu, and
    // there is no separate arrow section (the mock's Split has none).
    button->setPopupMode(QToolButton::DelayedPopup);
    button->setProperty(DolphinLayout::Segment, QString::fromLatin1(kind));
    group->layout()->addWidget(button);
}

// The style draws the glyph itself (the mock's plain line, square and cross),
// so window buttons don't change with the icon theme.
QToolButton *windowButton(QWidget *parent, const char *glyph, const QString &tip, const std::function<void()> &act)
{
    auto *button = new QToolButton(parent);
    button->setToolTip(tip);
    button->setAutoRaise(true);
    button->setFocusPolicy(Qt::NoFocus);
    button->setProperty(DolphinLayout::FlatButton, QString::fromLatin1(glyph));
    QObject::connect(button, &QToolButton::clicked, button, act);
    return button;
}

// Row 1 of the mock: Dolphin's back/forward/up, then the folder title and the
// window buttons. They are toolbar widgets kept at the end of the toolbar, so
// KXMLGUI's own actions stay in front even if it re-plugs them.
class TitleRow final : public QObject
{
public:
    explicit TitleRow(QToolBar *bar)
        : QObject(bar)
        , m_bar(bar)
        , m_title(new QLabel(bar))
    {
        QWidget *window = bar->window();
        QFont font = m_title->font();
        font.setPixelSize(kTitlePixelSize);
        font.setWeight(QFont::Medium);
        m_title->setFont(font);
        m_title->setForegroundRole(QPalette::Text);
        m_title->setContentsMargins(26, 0, 0, 0);
        m_title->setText(titleFor(window));

        auto *spacer = new QWidget(bar);
        spacer->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Preferred);

        // Hyprland suppresses maximize requests here, and "minimise" means the
        // special workspace (Super+Shift+S), so the buttons do what the binds do.
        auto *minimize = windowButton(bar, "minimize", QStringLiteral("Minimize"), [window] {
            onHyprland() ? hyprDispatch(QStringLiteral("hl.dsp.window.move({ workspace = \"special\" })")) : window->showMinimized();
        });
        auto *maximize = windowButton(bar, "maximize", QStringLiteral("Maximize"), [window] {
            if (onHyprland()) {
                hyprDispatch(QStringLiteral("hl.dsp.window.fullscreen({ mode = 1 })"));
            } else {
                window->isMaximized() ? window->showNormal() : window->showMaximized();
            }
        });
        auto *close = windowButton(bar, "close", QStringLiteral("Close"), [window] {
            window->close();
        });

        for (QWidget *item : {static_cast<QWidget *>(m_title), spacer, static_cast<QWidget *>(minimize), static_cast<QWidget *>(maximize), static_cast<QWidget *>(close)}) {
            QAction *action = m_bar->addWidget(item);
            action->setProperty(TitleRowItem, true);
            m_items.append(action);
        }
        window->installEventFilter(this);
        bar->installEventFilter(this);
    }

protected:
    bool eventFilter(QObject *object, QEvent *event) override
    {
        if (object == m_bar->window() && event->type() == QEvent::WindowTitleChange) {
            m_title->setText(titleFor(m_bar->window()));
        } else if (object == m_bar && event->type() == QEvent::ActionAdded && !m_reorderQueued) {
            if (!static_cast<QActionEvent *>(event)->action()->property(TitleRowItem).toBool()) {
                m_reorderQueued = true;
                QMetaObject::invokeMethod(this, [this] { keepLast(); }, Qt::QueuedConnection);
            }
        }
        return false;
    }

private:
    void keepLast()
    {
        m_reorderQueued = false;
        const auto actions = m_bar->actions();
        const qsizetype tail = actions.size() - m_items.size();
        if (tail >= 0 && actions.mid(tail) == m_items) {
            return;
        }
        for (QAction *action : std::as_const(m_items)) {
            m_bar->removeAction(action);
        }
        for (QAction *action : std::as_const(m_items)) {
            m_bar->addAction(action);
        }
    }

    QToolBar *m_bar;
    QLabel *m_title;
    QList<QAction *> m_items;
    bool m_reorderQueued = false;
};

// Row 2 of the mock: the path bar sits in the content column (Dolphin puts it
// at row 0 of each tab page once it leaves the toolbar), with the panel/Split
// pill, search and the menu beside it in the free cell at (0, 1).
void attachPathTools(QWidget *page)
{
    auto *grid = qobject_cast<QGridLayout *>(page->layout());
    if (grid == nullptr) {
        return;
    }
    // With the 16px dock separator this puts the content column 22px from the
    // sidebar card, as in the mock.
    grid->setContentsMargins(6, 0, 0, 0);

    // QToolBar re-reads its padding from the style on every style change, so the
    // side gaps live on a plain holder and the toolbar itself has none: the
    // cluster is exactly as tall as the path bar and lines up with it.
    auto *holder = new QWidget(page);
    holder->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    auto *holderLayout = new QHBoxLayout(holder);
    holderLayout->setContentsMargins(8, 0, 20, 0);
    holderLayout->setSpacing(0);

    auto *tools = new QToolBar(holder);
    tools->setObjectName(QLatin1String(DolphinLayout::PathTools));
    tools->setMovable(false);
    tools->setFloatable(false);
    tools->setToolButtonStyle(Qt::ToolButtonIconOnly);
    // At its preferred width; otherwise the grid squeezes it into an overflow arrow.
    tools->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed);
    tools->layout()->setContentsMargins(0, 0, 0, 0);
    tools->layout()->setSpacing(6);
    holderLayout->addWidget(tools);

    QAction *places = dolphinAction(page, "show_places_panel");
    if (places != nullptr) {
        // Set on the action: a button re-copies its action's icon on every toggle.
        places->setIcon(QIcon::fromTheme(QStringLiteral("sidebar-show-symbolic")));
    }
    QWidget *split = segmentGroup(tools, true);
    addSegment(split, places, "toggle", Qt::ToolButtonIconOnly);
    addSegment(split, dolphinAction(page, "split_view"), "plain", Qt::ToolButtonTextBesideIcon);
    tools->addWidget(split);

    // Dolphin shows its tab bar only once there are two tabs, so a one-tab
    // window had no visible way to open another (Ctrl+T and the ⋮ menu aside).
    if (QAction *newTab = dolphinAction(page, "new_tab")) {
        tools->addAction(newTab);
    }
    if (QAction *search = dolphinAction(page, "toggle_search")) {
        tools->addAction(search);
    }
    if (QAction *menu = dolphinAction(page, "hamburger_menu")) {
        // KHamburgerMenu hides the actions of the toolbar it joins from its menu.
        menu->setIcon(QIcon::fromTheme(QStringLiteral("overflow-menu")));
        tools->addAction(menu);
    }
    grid->addWidget(holder, 0, 1, Qt::AlignVCenter);
}

// The mock's status bar: text, zoom slider and the view-mode switch, without
// the "Zoom:" label or the free-space readout. Dolphin toggles both with
// setVisible(), so they are collapsed rather than hidden.
void attachStatusBar(QWidget *bar)
{
    QWidget *textLabel = nullptr;
    const auto children = bar->findChildren<QWidget *>();
    for (QWidget *child : children) {
        if (child->inherits("KSqueezedTextLabel")) {
            if (textLabel == nullptr) {
                textLabel = child;
            } else if (auto *zoomLabel = qobject_cast<QLabel *>(child)) {
                zoomLabel->setText(QString());
                zoomLabel->setMaximumWidth(0);
            }
        } else if (child->inherits("StatusBarSpaceInfo")) {
            child->setMaximumWidth(0);
        }
    }
    auto *row = textLabel != nullptr ? qobject_cast<QHBoxLayout *>(textLabel->parentWidget()->layout()) : nullptr;
    if (row == nullptr) {
        return;
    }
    QWidget *modes = segmentGroup(textLabel->parentWidget(), false);
    for (const char *name : {"icons", "compact", "details"}) {
        addSegment(modes, dolphinAction(bar, name), "choice", Qt::ToolButtonIconOnly);
    }
    row->addWidget(modes);
}
} // namespace

void DolphinLayout::attach(QWidget *widget)
{
    if (widget->property(Attached).toBool()) {
        return;
    }
    if (widget->inherits("KToolBar") && widget->objectName() == QLatin1String("mainToolBar")) {
        widget->setProperty(Attached, true);
        new TitleRow(static_cast<QToolBar *>(widget));
    } else if (widget->inherits("DolphinTabPage")) {
        widget->setProperty(Attached, true);
        attachPathTools(widget);
    } else if (widget->inherits("DolphinStatusBar")) {
        widget->setProperty(Attached, true);
        attachStatusBar(widget);
    }
}
