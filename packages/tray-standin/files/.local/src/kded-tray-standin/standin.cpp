// A stand-in for kded6's "statusnotifierwatcher" module, loaded instead of
// KDE's because ~/.local/lib/qt6/plugins comes first on QT_PLUGIN_PATH in
// the Hyprland session. Its metadata never loads and names no D-Bus service,
// so kded6 leaves org.kde.StatusNotifierWatcher to the Caelestia shell, whose
// own tray (Quickshell) must own that name for tray icons to appear.
// Plasma sessions don't use this plugin path and keep KDE's real module.
#include <KPluginFactory>
#include <kdedmodule.h>

class TrayStandIn : public KDEDModule
{
    Q_OBJECT
public:
    TrayStandIn(QObject *parent, const QList<QVariant> &)
        : KDEDModule(parent)
    {
    }
};

K_PLUGIN_CLASS_WITH_JSON(TrayStandIn, "standin.json")

#include "standin.moc"
