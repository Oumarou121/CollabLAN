import QtQuick
import QtQuick.Controls
import Themes
import "Login"
import "Home"
import "Users"
import "SharedFolder"

/*
 * Main - fenetre racine de CollabLAN.
 * Gere la navigation de base entre les ecrans via un StackView :
 *   Login -> Home (issue #6)
 * Applique le theme global (issue #7) via le singleton Themes.Theme.
 */
ApplicationWindow {
    id: window

    width: 1024
    height: 720
    minimumWidth: 640
    minimumHeight: 480
    visible: true
    title: qsTr("CollabLAN")
    color: Theme.background

    StackView {
        id: stackView
        anchors.fill: parent

        initialItem: loginViewComponent

        // Transitions simples (fondu) entre les ecrans
        pushEnter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
        }
        pushExit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 }
        }
        popEnter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
        }
        popExit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 }
        }
    }

    Component {
        id: loginViewComponent

        LoginView {
            onLoginSucceeded: function(username) {
                stackView.push(homeViewComponent, { username: username })
            }
        }
    }

    Component {
        id: homeViewComponent

        HomeView {
            onLogoutRequested: {
                stackView.pop(null) // revient a l'ecran Login (racine de la pile)
            }
            onUsersRequested: {
                stackView.push(usersViewComponent)
            }
            onSharedFoldersRequested: {
                stackView.push(sharedFolderViewComponent)
            }
        }
    }

    Component {
        id: usersViewComponent

        UsersView {
            onBackRequested: {
                stackView.pop()
            }
        }
    }

    Component {
        id: sharedFolderViewComponent

        SharedFolderView {
            onBackRequested: {
                stackView.pop()
            }
            onFolderOpened: function(folderId, folderName) {
                stackView.push(sharedFolderDetailComponent, { folderId: folderId, folderName: folderName })
            }
        }
    }

    Component {
        id: sharedFolderDetailComponent

        SharedFolderDetailView {
            onBackRequested: {
                stackView.pop()
            }
        }
    }
}
