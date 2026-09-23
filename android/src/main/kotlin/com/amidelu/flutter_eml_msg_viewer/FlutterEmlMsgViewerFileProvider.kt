package com.amidelu.flutter_eml_msg_viewer

import androidx.core.content.FileProvider

/**
 * Plugin-owned FileProvider subclass. Declaring `androidx.core.content.FileProvider`
 * directly collides in the manifest merger with any host app or other plugin that
 * declares the same class, which silently drops or overrides this plugin's authority.
 */
class FlutterEmlMsgViewerFileProvider : FileProvider()
