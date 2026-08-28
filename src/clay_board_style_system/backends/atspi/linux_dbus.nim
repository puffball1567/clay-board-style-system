when not defined(linux):
  {.error: "The Linux AT-SPI D-Bus transport is available only on Linux.".}

import std/[math, options, os, strutils, tables]

import ../../core/geometry
import ../../runtime/ui_root
import ./adapter

const
  glibLibrary = "libglib-2.0.so(|.0)"
  gobjectLibrary = "libgobject-2.0.so(|.0)"
  gioLibrary = "libgio-2.0.so(|.0)"

  accessibleInterface* = "org.a11y.atspi.Accessible"
  applicationInterface* = "org.a11y.atspi.Application"
  actionInterface* = "org.a11y.atspi.Action"
  componentInterface* = "org.a11y.atspi.Component"
  objectEventInterface* = "org.a11y.atspi.Event.Object"

  registryName = "org.a11y.atspi.Registry"
  registryPath = atspiRootPath
  socketInterface = "org.a11y.atspi.Socket"
  accessibilityBusName = "org.a11y.Bus"
  accessibilityBusPath = "/org/a11y/bus"
  accessibilityBusInterface = "org.a11y.Bus"

  interfaceXml = """
<node>
  <interface name="org.a11y.atspi.Accessible">
    <property name="version" type="u" access="read"/>
    <property name="Name" type="s" access="read"/>
    <property name="Description" type="s" access="read"/>
    <property name="Parent" type="(so)" access="read"/>
    <property name="ChildCount" type="i" access="read"/>
    <property name="Locale" type="s" access="read"/>
    <property name="AccessibleId" type="s" access="read"/>
    <property name="HelpText" type="s" access="read"/>
    <method name="GetChildAtIndex"><arg direction="in" type="i"/><arg direction="out" type="(so)"/></method>
    <method name="GetChildren"><arg direction="out" type="a(so)"/></method>
    <method name="GetIndexInParent"><arg direction="out" type="i"/></method>
    <method name="GetRelationSet"><arg direction="out" type="a(ua(so))"/></method>
    <method name="GetRole"><arg direction="out" type="u"/></method>
    <method name="GetRoleName"><arg direction="out" type="s"/></method>
    <method name="GetLocalizedRoleName"><arg direction="out" type="s"/></method>
    <method name="GetState"><arg direction="out" type="au"/></method>
    <method name="GetAttributes"><arg direction="out" type="a{ss}"/></method>
    <method name="GetApplication"><arg direction="out" type="(so)"/></method>
    <method name="GetInterfaces"><arg direction="out" type="as"/></method>
  </interface>
  <interface name="org.a11y.atspi.Application">
    <property name="ToolkitName" type="s" access="read"/>
    <property name="Version" type="s" access="read"/>
    <property name="ToolkitVersion" type="s" access="read"/>
    <property name="AtspiVersion" type="s" access="read"/>
    <property name="InterfaceVersion" type="u" access="read"/>
    <property name="Id" type="i" access="readwrite"/>
    <method name="GetLocale"><arg direction="in" type="u"/><arg direction="out" type="s"/></method>
    <method name="GetApplicationBusAddress"><arg direction="out" type="s"/></method>
  </interface>
  <interface name="org.a11y.atspi.Action">
    <property name="version" type="u" access="read"/>
    <property name="NActions" type="i" access="read"/>
    <method name="GetDescription"><arg direction="in" type="i"/><arg direction="out" type="s"/></method>
    <method name="GetName"><arg direction="in" type="i"/><arg direction="out" type="s"/></method>
    <method name="GetLocalizedName"><arg direction="in" type="i"/><arg direction="out" type="s"/></method>
    <method name="GetKeyBinding"><arg direction="in" type="i"/><arg direction="out" type="s"/></method>
    <method name="GetActions"><arg direction="out" type="a(sss)"/></method>
    <method name="DoAction"><arg direction="in" type="i"/><arg direction="out" type="b"/></method>
  </interface>
  <interface name="org.a11y.atspi.Component">
    <property name="version" type="u" access="read"/>
    <method name="Contains"><arg direction="in" type="i"/><arg direction="in" type="i"/><arg direction="in" type="u"/><arg direction="out" type="b"/></method>
    <method name="GetAccessibleAtPoint"><arg direction="in" type="i"/><arg direction="in" type="i"/><arg direction="in" type="u"/><arg direction="out" type="(so)"/></method>
    <method name="GetExtents"><arg direction="in" type="u"/><arg direction="out" type="(iiii)"/></method>
    <method name="GetPosition"><arg direction="in" type="u"/><arg direction="out" type="i"/><arg direction="out" type="i"/></method>
    <method name="GetSize"><arg direction="out" type="i"/><arg direction="out" type="i"/></method>
    <method name="GetLayer"><arg direction="out" type="u"/></method>
    <method name="GetMDIZOrder"><arg direction="out" type="n"/></method>
    <method name="GrabFocus"><arg direction="out" type="b"/></method>
    <method name="GetAlpha"><arg direction="out" type="d"/></method>
    <method name="SetExtents"><arg direction="in" type="i"/><arg direction="in" type="i"/><arg direction="in" type="i"/><arg direction="in" type="i"/><arg direction="in" type="u"/><arg direction="out" type="b"/></method>
    <method name="SetPosition"><arg direction="in" type="i"/><arg direction="in" type="i"/><arg direction="in" type="u"/><arg direction="out" type="b"/></method>
    <method name="SetSize"><arg direction="in" type="i"/><arg direction="in" type="i"/><arg direction="out" type="b"/></method>
    <method name="ScrollTo"><arg direction="in" type="u"/><arg direction="out" type="b"/></method>
    <method name="ScrollToPoint"><arg direction="in" type="u"/><arg direction="in" type="i"/><arg direction="in" type="i"/><arg direction="out" type="b"/></method>
  </interface>
</node>
"""

type
  GVariant = object
  GVariantType = object
  GMainContext = object
  GDBusConnection = object
  GDBusNodeInfo = object
  GDBusInterfaceInfo = object
  GDBusMethodInvocation = object
  GCancellable = object
  GDBusAuthObserver = object

  GError {.bycopy.} = object
    domain: uint32
    code: int32
    message: cstring

  GDBusMethodCallProc = proc(
    connection: ptr GDBusConnection;
    sender, objectPath, interfaceName, methodName: cstring;
    parameters: ptr GVariant;
    invocation: ptr GDBusMethodInvocation;
    userData: pointer
  ) {.cdecl.}

  GDBusGetPropertyProc = proc(
    connection: ptr GDBusConnection;
    sender, objectPath, interfaceName, propertyName: cstring;
    error: ptr ptr GError;
    userData: pointer
  ): ptr GVariant {.cdecl.}

  GDBusSetPropertyProc = proc(
    connection: ptr GDBusConnection;
    sender, objectPath, interfaceName, propertyName: cstring;
    value: ptr GVariant;
    error: ptr ptr GError;
    userData: pointer
  ): int32 {.cdecl.}

  GDBusInterfaceVTable {.bycopy.} = object
    methodCall: GDBusMethodCallProc
    getProperty: GDBusGetPropertyProc
    setProperty: GDBusSetPropertyProc
    padding: array[8, pointer]

  LinuxAtspiScreenOriginProc* = proc(): Vec2 {.closure.}

  LinuxAtspiOptions* = object
    screenOrigin*: LinuxAtspiScreenOriginProc

  LinuxAtspiTransport* = ref object
    ui: UiRoot
    options: LinuxAtspiOptions
    context: ptr GMainContext
    connection: ptr GDBusConnection
    nodeInfo: ptr GDBusNodeInfo
    registrations: Table[string, seq[uint32]]
    nodeIndexByPath: Table[string, int]
    snapshot: AtspiSnapshot
    uniqueName: string
    registryBusName: string
    registryObjectPath: string
    applicationId: int32
    published: bool
    embedded: bool
    closed: bool
    lastError*: string

proc g_bus_get_sync(busType: int32; cancellable: ptr GCancellable;
    error: ptr ptr GError): ptr GDBusConnection {.cdecl, importc, dynlib: gioLibrary.}
proc g_dbus_connection_new_for_address_sync(address: cstring; flags: int32;
    observer: ptr GDBusAuthObserver; cancellable: ptr GCancellable;
    error: ptr ptr GError): ptr GDBusConnection {.cdecl, importc, dynlib: gioLibrary.}
proc g_dbus_connection_call_sync(connection: ptr GDBusConnection;
    busName, objectPath, interfaceName, methodName: cstring;
    parameters: ptr GVariant; replyType: ptr GVariantType; flags: int32;
    timeoutMs: int32; cancellable: ptr GCancellable;
    error: ptr ptr GError): ptr GVariant {.cdecl, importc, dynlib: gioLibrary.}
proc g_dbus_connection_get_unique_name(connection: ptr GDBusConnection): cstring
    {.cdecl, importc, dynlib: gioLibrary.}
proc g_dbus_connection_register_object(connection: ptr GDBusConnection;
    objectPath: cstring; interfaceInfo: ptr GDBusInterfaceInfo;
    vtable: ptr GDBusInterfaceVTable; userData: pointer;
    destroyNotify: pointer; error: ptr ptr GError): uint32
    {.cdecl, importc, dynlib: gioLibrary.}
proc g_dbus_connection_unregister_object(connection: ptr GDBusConnection;
    registrationId: uint32): int32 {.cdecl, importc, dynlib: gioLibrary.}
proc g_dbus_connection_emit_signal(connection: ptr GDBusConnection;
    destinationBusName, objectPath, interfaceName, signalName: cstring;
    parameters: ptr GVariant; error: ptr ptr GError): int32
    {.cdecl, importc, dynlib: gioLibrary.}
proc g_dbus_connection_close_sync(connection: ptr GDBusConnection;
    cancellable: ptr GCancellable; error: ptr ptr GError): int32
    {.cdecl, importc, dynlib: gioLibrary.}
proc g_dbus_node_info_new_for_xml(xmlData: cstring;
    error: ptr ptr GError): ptr GDBusNodeInfo {.cdecl, importc, dynlib: gioLibrary.}
proc g_dbus_node_info_lookup_interface(info: ptr GDBusNodeInfo;
    name: cstring): ptr GDBusInterfaceInfo {.cdecl, importc, dynlib: gioLibrary.}
proc g_dbus_node_info_unref(info: ptr GDBusNodeInfo)
    {.cdecl, importc, dynlib: gioLibrary.}
proc g_dbus_method_invocation_return_value(invocation: ptr GDBusMethodInvocation;
    parameters: ptr GVariant) {.cdecl, importc, dynlib: gioLibrary.}
proc g_dbus_method_invocation_return_dbus_error(invocation: ptr GDBusMethodInvocation;
    errorName, errorMessage: cstring) {.cdecl, importc, dynlib: gioLibrary.}

proc g_main_context_new(): ptr GMainContext {.cdecl, importc, dynlib: glibLibrary.}
proc g_main_context_unref(context: ptr GMainContext) {.cdecl, importc, dynlib: glibLibrary.}
proc g_main_context_push_thread_default(context: ptr GMainContext)
    {.cdecl, importc, dynlib: glibLibrary.}
proc g_main_context_pop_thread_default(context: ptr GMainContext)
    {.cdecl, importc, dynlib: glibLibrary.}
proc g_main_context_pending(context: ptr GMainContext): int32
    {.cdecl, importc, dynlib: glibLibrary.}
proc g_main_context_iteration(context: ptr GMainContext; mayBlock: int32): int32
    {.cdecl, importc, dynlib: glibLibrary.}
proc g_error_free(error: ptr GError) {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_unref(value: ptr GVariant) {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_new_boolean(value: int32): ptr GVariant {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_new_int16(value: int16): ptr GVariant {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_new_int32(value: int32): ptr GVariant {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_new_uint32(value: uint32): ptr GVariant {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_new_double(value: float64): ptr GVariant {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_new_string(value: cstring): ptr GVariant {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_new_object_path(value: cstring): ptr GVariant {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_new_variant(value: ptr GVariant): ptr GVariant {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_new_array(childType: ptr GVariantType; children: ptr ptr GVariant;
    childCount: csize_t): ptr GVariant {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_new_tuple(children: ptr ptr GVariant;
    childCount: csize_t): ptr GVariant {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_new_dict_entry(key, value: ptr GVariant): ptr GVariant
    {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_get_child_value(value: ptr GVariant; index: csize_t): ptr GVariant
    {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_get_int32(value: ptr GVariant): int32 {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_get_uint32(value: ptr GVariant): uint32 {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_get_string(value: ptr GVariant; length: ptr csize_t): cstring
    {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_type_new(signature: cstring): ptr GVariantType
    {.cdecl, importc, dynlib: glibLibrary.}
proc g_variant_type_free(valueType: ptr GVariantType) {.cdecl, importc, dynlib: glibLibrary.}

proc g_object_unref(value: pointer) {.cdecl, importc, dynlib: gobjectLibrary.}

proc cstringValue(value: cstring): string =
  if value == nil: "" else: $value

proc consumeError(error: var ptr GError): string =
  if error == nil:
    return "Unknown GLib error"
  result = error.message.cstringValue()
  g_error_free(error)
  error = nil

proc tupleVariant(children: openArray[ptr GVariant]): ptr GVariant =
  if children.len == 0:
    return g_variant_new_tuple(nil, 0)
  g_variant_new_tuple(cast[ptr ptr GVariant](unsafeAddr children[0]), children.len.csize_t)

proc arrayVariant(elementSignature: string;
    children: openArray[ptr GVariant]): ptr GVariant =
  let elementType = g_variant_type_new(elementSignature.cstring)
  if elementType == nil:
    return nil
  defer:
    g_variant_type_free(elementType)
  let values =
    if children.len == 0: nil
    else: cast[ptr ptr GVariant](unsafeAddr children[0])
  g_variant_new_array(elementType, values, children.len.csize_t)

proc objectReference(busName, objectPath: string): ptr GVariant =
  tupleVariant([
    g_variant_new_string(busName.cstring),
    g_variant_new_object_path(objectPath.cstring)
  ])

proc output(value: ptr GVariant): ptr GVariant =
  tupleVariant([value])

proc reply(invocation: ptr GDBusMethodInvocation; value: ptr GVariant = nil) =
  g_dbus_method_invocation_return_value(
    invocation,
    if value == nil: tupleVariant([]) else: value
  )

proc replyError(invocation: ptr GDBusMethodInvocation; message: string) =
  g_dbus_method_invocation_return_dbus_error(
    invocation,
    "org.a11y.atspi.Error.InvalidObject".cstring,
    message.cstring
  )

proc child(parameters: ptr GVariant; index: int): ptr GVariant =
  if parameters == nil: nil
  else: g_variant_get_child_value(parameters, index.csize_t)

proc childInt(parameters: ptr GVariant; index: int): int32 =
  let value = parameters.child(index)
  if value == nil:
    return 0
  defer:
    g_variant_unref(value)
  g_variant_get_int32(value)

proc childUInt(parameters: ptr GVariant; index: int): uint32 =
  let value = parameters.child(index)
  if value == nil:
    return 0
  defer:
    g_variant_unref(value)
  g_variant_get_uint32(value)

proc variantString(value: ptr GVariant): string =
  if value == nil:
    return ""
  g_variant_get_string(value, nil).cstringValue()

proc nodeAt(transport: LinuxAtspiTransport; path: string): Option[AtspiNode] =
  if transport.nodeIndexByPath.hasKey(path):
    let index = transport.nodeIndexByPath[path]
    if index >= 0 and index < transport.snapshot.nodes.len:
      return some(transport.snapshot.nodes[index])
  none(AtspiNode)

proc isDescendantOrSelf(transport: LinuxAtspiTransport; candidatePath,
    ancestorPath: string): bool =
  var currentPath = candidatePath
  var visited = initTable[string, bool]()
  while currentPath != atspiNullPath and not visited.hasKey(currentPath):
    if currentPath == ancestorPath:
      return true
    visited[currentPath] = true
    let current = transport.nodeAt(currentPath)
    if current.isNone:
      return false
    currentPath = current.get.parentPath
  false

proc validAtspiObjectPath*(path: string): bool =
  if path == atspiRootPath:
    return true
  const prefix = "/org/a11y/atspi/accessible/node_"
  if not path.startsWith(prefix) or path.len == prefix.len:
    return false
  for ch in path[prefix.len .. ^1]:
    if ch notin {'0' .. '9'}:
      return false
  true

proc interfaceNames*(node: AtspiNode): seq[string] =
  if atiAccessible in node.interfaces:
    result.add accessibleInterface
  if atiApplication in node.interfaces:
    result.add applicationInterface
  if atiAction in node.interfaces:
    result.add actionInterface
  if atiComponent in node.interfaces:
    result.add componentInterface

proc roleCode*(role: AtspiRole): uint32 =
  case role
  of atrApplication: 75
  of atrPanel: 39
  of atrPushButton: 43
  of atrCheckBox: 7
  of atrRadioButton: 44
  of atrEntry: 79
  of atrText: 61
  of atrComboBox: 11
  of atrListItem: 32
  of atrSlider: 51
  of atrProgressBar: 42
  of atrList: 98
  of atrPageTabList: 38
  of atrPageTab: 37
  of atrDialog: 16
  of atrImage: 27
  of atrStatic: 116
  of atrLink: 88
  of atrToggleButton: 62
  of atrPasswordText: 40

proc roleName*(role: AtspiRole): string =
  case role
  of atrApplication: "application"
  of atrPanel: "panel"
  of atrPushButton: "push button"
  of atrCheckBox: "check box"
  of atrRadioButton: "radio button"
  of atrEntry: "entry"
  of atrText: "text"
  of atrComboBox: "combo box"
  of atrListItem: "list item"
  of atrSlider: "slider"
  of atrProgressBar: "progress bar"
  of atrList: "list box"
  of atrPageTabList: "page tab list"
  of atrPageTab: "page tab"
  of atrDialog: "dialog"
  of atrImage: "image"
  of atrStatic: "static"
  of atrLink: "link"
  of atrToggleButton: "toggle button"
  of atrPasswordText: "password text"

proc stateCode(state: AtspiState): uint32 =
  case state
  of atsActive: 1
  of atsChecked: 4
  of atsEnabled: 8
  of atsExpanded: 10
  of atsFocusable: 11
  of atsFocused: 12
  of atsSelected: 23
  of atsSensitive: 24
  of atsShowing: 25
  of atsVisible: 30
  of atsInvalid: 36

proc stateName(state: AtspiState): string =
  case state
  of atsActive: "active"
  of atsChecked: "checked"
  of atsEnabled: "enabled"
  of atsExpanded: "expanded"
  of atsFocusable: "focusable"
  of atsFocused: "focused"
  of atsSelected: "selected"
  of atsSensitive: "sensitive"
  of atsShowing: "showing"
  of atsVisible: "visible"
  of atsInvalid: "invalid-entry"

proc stateCodes*(states: set[AtspiState]): seq[uint32] =
  for state in AtspiState:
    if state in states:
      result.add state.stateCode()

proc localeName(): string =
  result = getEnv("LC_ALL")
  if result.len == 0:
    result = getEnv("LC_MESSAGES")
  if result.len == 0:
    result = getEnv("LANG", "C")

proc parentReference(transport: LinuxAtspiTransport;
    node: AtspiNode): ptr GVariant =
  if node.objectPath == atspiRootPath and transport.registryBusName.len > 0:
    return objectReference(transport.registryBusName, transport.registryObjectPath)
  if node.parentPath == atspiNullPath:
    return objectReference("", atspiNullPath)
  objectReference(transport.uniqueName, node.parentPath)

proc attributesVariant(node: AtspiNode): ptr GVariant =
  var entries: seq[ptr GVariant]
  if node.positionInSet.isSome:
    entries.add g_variant_new_dict_entry(
      g_variant_new_string("posinset"),
      g_variant_new_string(($node.positionInSet.get).cstring)
    )
  if node.setSize.isSome:
    entries.add g_variant_new_dict_entry(
      g_variant_new_string("setsize"),
      g_variant_new_string(($node.setSize.get).cstring)
    )
  arrayVariant("{ss}", entries)

proc interfaceArray(node: AtspiNode): ptr GVariant =
  var values: seq[ptr GVariant]
  for name in node.interfaceNames():
    values.add g_variant_new_string(name.cstring)
  arrayVariant("s", values)

proc stateArray(node: AtspiNode): ptr GVariant =
  var values: seq[ptr GVariant]
  for code in node.states.stateCodes():
    values.add g_variant_new_uint32(code)
  arrayVariant("u", values)

proc childrenArray(transport: LinuxAtspiTransport;
    node: AtspiNode): ptr GVariant =
  var values: seq[ptr GVariant]
  for path in node.childPaths:
    values.add objectReference(transport.uniqueName, path)
  arrayVariant("(so)", values)

proc relationArray(): ptr GVariant =
  arrayVariant("(ua(so))", [])

proc actionArray(node: AtspiNode): ptr GVariant =
  var values: seq[ptr GVariant]
  for action in node.actions:
    values.add tupleVariant([
      g_variant_new_string(action.cstring),
      g_variant_new_string(""),
      g_variant_new_string("")
    ])
  arrayVariant("(sss)", values)

proc localBounds(transport: LinuxAtspiTransport; node: AtspiNode;
    coordType: uint32): Rect =
  if node.bounds.isNone:
    return rect(0, 0, 0, 0)
  result = node.bounds.get
  case coordType
  of 0:
    if transport.options.screenOrigin != nil:
      let origin = transport.options.screenOrigin()
      result.x += origin.x
      result.y += origin.y
  of 2:
    let parent = transport.nodeAt(node.parentPath)
    if parent.isSome and parent.get.bounds.isSome:
      result.x -= parent.get.bounds.get.x
      result.y -= parent.get.bounds.get.y
  else:
    discard

proc pointInWindow(transport: LinuxAtspiTransport; node: AtspiNode;
    x, y: int32; coordType: uint32): Vec2 =
  result = vec2(x.float32, y.float32)
  case coordType
  of 0:
    if transport.options.screenOrigin != nil:
      let origin = transport.options.screenOrigin()
      result.x -= origin.x
      result.y -= origin.y
  of 2:
    let parent = transport.nodeAt(node.parentPath)
    if parent.isSome and parent.get.bounds.isSome:
      result.x += parent.get.bounds.get.x
      result.y += parent.get.bounds.get.y
  else:
    discard

proc returnAccessibleMethod(transport: LinuxAtspiTransport; node: AtspiNode;
    methodName: string; parameters: ptr GVariant;
    invocation: ptr GDBusMethodInvocation) =
  case methodName
  of "GetChildAtIndex":
    let index = parameters.childInt(0)
    if index < 0 or index >= node.childPaths.len.int32:
      invocation.replyError("Accessible child index is out of range")
    else:
      invocation.reply(output(objectReference(
        transport.uniqueName,
        node.childPaths[index.int]
      )))
  of "GetChildren":
    invocation.reply(output(transport.childrenArray(node)))
  of "GetIndexInParent":
    var index = -1'i32
    let parent = transport.nodeAt(node.parentPath)
    if parent.isSome:
      for candidateIndex, childPath in parent.get.childPaths:
        if childPath == node.objectPath:
          index = candidateIndex.int32
          break
    invocation.reply(output(g_variant_new_int32(index)))
  of "GetRelationSet":
    invocation.reply(output(relationArray()))
  of "GetRole":
    invocation.reply(output(g_variant_new_uint32(node.role.roleCode())))
  of "GetRoleName", "GetLocalizedRoleName":
    invocation.reply(output(g_variant_new_string(node.role.roleName().cstring)))
  of "GetState":
    invocation.reply(output(node.stateArray()))
  of "GetAttributes":
    invocation.reply(output(node.attributesVariant()))
  of "GetApplication":
    invocation.reply(output(objectReference(transport.uniqueName, atspiRootPath)))
  of "GetInterfaces":
    invocation.reply(output(node.interfaceArray()))
  else:
    invocation.replyError("Unsupported Accessible method: " & methodName)

proc returnApplicationMethod(transport: LinuxAtspiTransport; methodName: string;
    invocation: ptr GDBusMethodInvocation) =
  case methodName
  of "GetLocale":
    invocation.reply(output(g_variant_new_string(localeName().cstring)))
  of "GetApplicationBusAddress":
    invocation.reply(output(g_variant_new_string("")))
  else:
    invocation.replyError("Unsupported Application method: " & methodName)

proc actionAt(node: AtspiNode; index: int32): Option[string] =
  if index < 0 or index >= node.actions.len.int32:
    return none(string)
  some(node.actions[index.int])

proc returnActionMethod(transport: LinuxAtspiTransport; node: AtspiNode;
    methodName: string; parameters: ptr GVariant;
    invocation: ptr GDBusMethodInvocation) =
  case methodName
  of "GetDescription", "GetKeyBinding":
    let action = node.actionAt(parameters.childInt(0))
    if action.isNone:
      invocation.replyError("Action index is out of range")
    else:
      invocation.reply(output(g_variant_new_string("")))
  of "GetName", "GetLocalizedName":
    let action = node.actionAt(parameters.childInt(0))
    if action.isNone:
      invocation.replyError("Action index is out of range")
    else:
      invocation.reply(output(g_variant_new_string(action.get.cstring)))
  of "GetActions":
    invocation.reply(output(node.actionArray()))
  of "DoAction":
    let action = node.actionAt(parameters.childInt(0))
    let performed = action.isSome and
      transport.ui.performAtspiAction(
        transport.snapshot,
        node.objectPath,
        action.get
      )
    invocation.reply(output(g_variant_new_boolean(performed.int32)))
  else:
    invocation.replyError("Unsupported Action method: " & methodName)

proc returnComponentMethod(transport: LinuxAtspiTransport; node: AtspiNode;
    methodName: string; parameters: ptr GVariant;
    invocation: ptr GDBusMethodInvocation) =
  case methodName
  of "Contains":
    let point = transport.pointInWindow(
      node,
      parameters.childInt(0),
      parameters.childInt(1),
      parameters.childUInt(2)
    )
    let contains = node.bounds.isSome and node.bounds.get.contains(point)
    invocation.reply(output(g_variant_new_boolean(contains.int32)))
  of "GetAccessibleAtPoint":
    let point = transport.pointInWindow(
      node,
      parameters.childInt(0),
      parameters.childInt(1),
      parameters.childUInt(2)
    )
    var path = atspiNullPath
    for index in countdown(transport.snapshot.nodes.high, 0):
      let candidate = transport.snapshot.nodes[index]
      if transport.isDescendantOrSelf(candidate.objectPath, node.objectPath) and
          atsShowing in candidate.states and atsVisible in candidate.states and
          candidate.bounds.isSome and candidate.bounds.get.contains(point):
        path = candidate.objectPath
        break
    invocation.reply(output(objectReference(
      if path == atspiNullPath: "" else: transport.uniqueName,
      path
    )))
  of "GetExtents":
    let bounds = transport.localBounds(node, parameters.childUInt(0))
    invocation.reply(output(tupleVariant([
      g_variant_new_int32(bounds.x.round.int32),
      g_variant_new_int32(bounds.y.round.int32),
      g_variant_new_int32(bounds.w.round.int32),
      g_variant_new_int32(bounds.h.round.int32)
    ])))
  of "GetPosition":
    let bounds = transport.localBounds(node, parameters.childUInt(0))
    invocation.reply(tupleVariant([
      g_variant_new_int32(bounds.x.round.int32),
      g_variant_new_int32(bounds.y.round.int32)
    ]))
  of "GetSize":
    let bounds = transport.localBounds(node, 1)
    invocation.reply(tupleVariant([
      g_variant_new_int32(bounds.w.round.int32),
      g_variant_new_int32(bounds.h.round.int32)
    ]))
  of "GetLayer":
    invocation.reply(output(g_variant_new_uint32(
      if node.objectPath == atspiRootPath: 7'u32 else: 3'u32
    )))
  of "GetMDIZOrder":
    invocation.reply(output(g_variant_new_int16(-1)))
  of "GrabFocus":
    let accepted = node.source.isSome and atsFocusable in node.states and
      atsEnabled in node.states and atsSensitive in node.states and
      atsShowing in node.states and atsVisible in node.states
    if accepted:
      transport.ui.requestFocus(node.source)
    invocation.reply(output(g_variant_new_boolean(accepted.int32)))
  of "GetAlpha":
    invocation.reply(output(g_variant_new_double(1.0)))
  of "SetExtents", "SetPosition", "SetSize", "ScrollTo", "ScrollToPoint":
    invocation.reply(output(g_variant_new_boolean(0)))
  else:
    invocation.replyError("Unsupported Component method: " & methodName)

proc methodCall(connection: ptr GDBusConnection;
    sender, objectPath, interfaceName, methodName: cstring;
    parameters: ptr GVariant; invocation: ptr GDBusMethodInvocation;
    userData: pointer) {.cdecl.} =
  try:
    let transport = cast[LinuxAtspiTransport](userData)
    if transport == nil or transport.closed:
      invocation.replyError("The CBSS accessibility transport is closed")
      return
    let path = objectPath.cstringValue()
    let node = transport.nodeAt(path)
    if node.isNone:
      invocation.replyError("Unknown accessible object: " & path)
      return
    case interfaceName.cstringValue()
    of accessibleInterface:
      transport.returnAccessibleMethod(
        node.get, methodName.cstringValue(), parameters, invocation
      )
    of applicationInterface:
      transport.returnApplicationMethod(methodName.cstringValue(), invocation)
    of actionInterface:
      transport.returnActionMethod(
        node.get, methodName.cstringValue(), parameters, invocation
      )
    of componentInterface:
      transport.returnComponentMethod(
        node.get, methodName.cstringValue(), parameters, invocation
      )
    else:
      invocation.replyError("Unknown accessibility interface")
  except Exception as error:
    invocation.replyError("CBSS accessibility dispatch failed: " & error.msg)

proc getProperty(connection: ptr GDBusConnection;
    sender, objectPath, interfaceName, propertyName: cstring;
    error: ptr ptr GError; userData: pointer): ptr GVariant {.cdecl.} =
  try:
    let transport = cast[LinuxAtspiTransport](userData)
    if transport == nil or transport.closed:
      return nil
    let node = transport.nodeAt(objectPath.cstringValue())
    if node.isNone:
      return nil
    let property = propertyName.cstringValue()
    case interfaceName.cstringValue()
    of accessibleInterface:
      case property
      of "version": g_variant_new_uint32(1)
      of "Name": g_variant_new_string(node.get.name.cstring)
      of "Description": g_variant_new_string(node.get.description.cstring)
      of "Parent": transport.parentReference(node.get)
      of "ChildCount": g_variant_new_int32(node.get.childPaths.len.int32)
      of "Locale": g_variant_new_string(localeName().cstring)
      of "AccessibleId": g_variant_new_string(node.get.accessibleId.cstring)
      of "HelpText": g_variant_new_string("")
      else: nil
    of applicationInterface:
      case property
      of "ToolkitName":
        g_variant_new_string(transport.snapshot.toolkitName.cstring)
      of "Version", "ToolkitVersion":
        g_variant_new_string(transport.snapshot.toolkitVersion.cstring)
      of "AtspiVersion": g_variant_new_string("2.1")
      of "InterfaceVersion": g_variant_new_uint32(1)
      of "Id": g_variant_new_int32(transport.applicationId)
      else: nil
    of actionInterface:
      case property
      of "version": g_variant_new_uint32(1)
      of "NActions": g_variant_new_int32(node.get.actions.len.int32)
      else: nil
    of componentInterface:
      if property == "version": g_variant_new_uint32(1) else: nil
    else:
      nil
  except Exception:
    nil

proc setProperty(connection: ptr GDBusConnection;
    sender, objectPath, interfaceName, propertyName: cstring;
    value: ptr GVariant; error: ptr ptr GError;
    userData: pointer): int32 {.cdecl.} =
  try:
    let transport = cast[LinuxAtspiTransport](userData)
    if transport != nil and not transport.closed and
        objectPath.cstringValue() == atspiRootPath and
        interfaceName.cstringValue() == applicationInterface and
        propertyName.cstringValue() == "Id":
      transport.applicationId = g_variant_get_int32(value)
      return 1
  except Exception:
    discard
  0

var interfaceVTable = GDBusInterfaceVTable(
  methodCall: methodCall,
  getProperty: getProperty,
  setProperty: setProperty
)

proc unregisterPath(transport: LinuxAtspiTransport; path: string) =
  if not transport.registrations.hasKey(path):
    return
  for registration in transport.registrations[path]:
    discard g_dbus_connection_unregister_object(
      transport.connection,
      registration
    )
  transport.registrations.del(path)

proc registerNode(transport: LinuxAtspiTransport; node: AtspiNode): bool =
  if not node.objectPath.validAtspiObjectPath():
    transport.lastError = "Unsafe AT-SPI object path: " & node.objectPath
    return false
  # GDBus dispatches object callbacks on the thread-default context that was
  # active at registration time. Keep that context identical to poll().
  g_main_context_push_thread_default(transport.context)
  defer:
    g_main_context_pop_thread_default(transport.context)
  var registrations: seq[uint32]
  for interfaceName in node.interfaceNames():
    let interfaceInfo = g_dbus_node_info_lookup_interface(
      transport.nodeInfo,
      interfaceName.cstring
    )
    if interfaceInfo == nil:
      transport.lastError = "Missing AT-SPI introspection interface: " & interfaceName
      break
    var error: ptr GError
    let registration = g_dbus_connection_register_object(
      transport.connection,
      node.objectPath.cstring,
      interfaceInfo,
      addr interfaceVTable,
      cast[pointer](transport),
      nil,
      addr error
    )
    if registration == 0:
      transport.lastError = error.consumeError()
      break
    registrations.add registration
  if registrations.len != node.interfaceNames().len:
    for registration in registrations:
      discard g_dbus_connection_unregister_object(
        transport.connection,
        registration
      )
    return false
  transport.registrations[node.objectPath] = registrations
  true

proc embed(transport: LinuxAtspiTransport): bool =
  let plug = objectReference(transport.uniqueName, atspiRootPath)
  var error: ptr GError
  let response = g_dbus_connection_call_sync(
    transport.connection,
    registryName,
    registryPath,
    socketInterface,
    "Embed",
    tupleVariant([plug]),
    nil,
    0,
    5_000,
    nil,
    addr error
  )
  if response == nil:
    transport.lastError = error.consumeError()
    return false
  defer:
    g_variant_unref(response)
  let socket = response.child(0)
  if socket == nil:
    transport.lastError = "AT-SPI registry returned no root object"
    return false
  defer:
    g_variant_unref(socket)
  let busName = socket.child(0)
  let objectPath = socket.child(1)
  if busName == nil or objectPath == nil:
    if busName != nil: g_variant_unref(busName)
    if objectPath != nil: g_variant_unref(objectPath)
    transport.lastError = "AT-SPI registry returned an invalid root reference"
    return false
  transport.registryBusName = busName.variantString()
  transport.registryObjectPath = objectPath.variantString()
  g_variant_unref(busName)
  g_variant_unref(objectPath)
  transport.embedded = true
  true

proc emptyEventProperties(): ptr GVariant =
  arrayVariant("{sv}", [])

proc eventParameters(detail: string; first, second: int32;
    value: ptr GVariant): ptr GVariant =
  tupleVariant([
    g_variant_new_string(detail.cstring),
    g_variant_new_int32(first),
    g_variant_new_int32(second),
    g_variant_new_variant(value),
    emptyEventProperties()
  ])

proc emitEvent(transport: LinuxAtspiTransport; objectPath, signalName,
    detail: string; first = 0'i32; second = 0'i32;
    value: ptr GVariant = nil) =
  var error: ptr GError
  let payload =
    if value == nil: g_variant_new_string("")
    else: value
  if g_dbus_connection_emit_signal(
      transport.connection,
      nil,
      objectPath.cstring,
      objectEventInterface,
      signalName.cstring,
      eventParameters(detail, first, second, payload),
      addr error
  ) == 0:
    transport.lastError = error.consumeError()

proc emitChanges(transport: LinuxAtspiTransport; previous: AtspiSnapshot;
    changes: openArray[AtspiChange]) =
  for change in changes:
    let current = transport.nodeAt(change.objectPath)
    let old = previous.nodeAt(change.objectPath)
    case change.kind
    of ackAdded:
      if current.isSome:
        transport.emitEvent(
          current.get.parentPath,
          "ChildrenChanged",
          "add",
          value = objectReference(transport.uniqueName, change.objectPath)
        )
    of ackRemoved:
      if old.isSome:
        transport.emitEvent(
          old.get.parentPath,
          "ChildrenChanged",
          "remove",
          value = objectReference(transport.uniqueName, change.objectPath)
        )
    of ackName:
      if current.isSome:
        transport.emitEvent(
          change.objectPath,
          "PropertyChange",
          "accessible-name",
          value = g_variant_new_string(current.get.name.cstring)
        )
    of ackDescription:
      if current.isSome:
        transport.emitEvent(
          change.objectPath,
          "PropertyChange",
          "accessible-description",
          value = g_variant_new_string(current.get.description.cstring)
        )
    of ackValue:
      if current.isSome:
        transport.emitEvent(
          change.objectPath,
          "PropertyChange",
          "accessible-value",
          value = g_variant_new_string(current.get.value.cstring)
        )
    of ackState:
      if current.isSome and old.isSome:
        for state in AtspiState:
          let wasEnabled = state in old.get.states
          let isEnabled = state in current.get.states
          if wasEnabled != isEnabled:
            transport.emitEvent(
              change.objectPath,
              "StateChanged",
              state.stateName(),
              isEnabled.int32
            )
    of ackBounds:
      if current.isSome and current.get.bounds.isSome:
        let bounds = current.get.bounds.get
        transport.emitEvent(
          change.objectPath,
          "BoundsChanged",
          "",
          value = tupleVariant([
            g_variant_new_int32(bounds.x.round.int32),
            g_variant_new_int32(bounds.y.round.int32),
            g_variant_new_int32(bounds.w.round.int32),
            g_variant_new_int32(bounds.h.round.int32)
          ])
        )
    of ackChildren:
      transport.emitEvent(change.objectPath, "ChildrenChanged", "reorder")
    of ackSetPosition:
      transport.emitEvent(change.objectPath, "AttributesChanged", "set-position")

proc validAtspiSnapshot*(snapshot: AtspiSnapshot): bool =
  if snapshot.nodes.len == 0 or snapshot.nodes[0].objectPath != atspiRootPath:
    return false
  let root = snapshot.nodes[0]
  if root.parentPath != atspiNullPath or root.role != atrApplication or
      atiApplication notin root.interfaces:
    return false

  const supportedInterfaces = {
    atiAccessible,
    atiAction,
    atiApplication,
    atiComponent
  }
  var indexByPath = initTable[string, int]()
  for index, node in snapshot.nodes:
    if not node.objectPath.validAtspiObjectPath() or
        indexByPath.hasKey(node.objectPath) or
        atiAccessible notin node.interfaces or
        not (node.interfaces <= supportedInterfaces) or
        ((atiAction in node.interfaces) != (node.actions.len > 0)) or
        ((atiComponent in node.interfaces) != node.bounds.isSome) or
        (node.objectPath != atspiRootPath and
          (atiApplication in node.interfaces or node.role == atrApplication)):
      return false
    for action in node.actions:
      if action != "activate":
        return false
    indexByPath[node.objectPath] = index

  var incoming = initTable[string, int]()
  for index, node in snapshot.nodes:
    if index > 0 and (node.parentPath == node.objectPath or
        not indexByPath.hasKey(node.parentPath)):
      return false
    var childSet = initTable[string, bool]()
    for childPath in node.childPaths:
      if childPath == node.objectPath or childPath == atspiRootPath or
          childSet.hasKey(childPath) or not indexByPath.hasKey(childPath) or
          snapshot.nodes[indexByPath[childPath]].parentPath != node.objectPath:
        return false
      childSet[childPath] = true
      incoming[childPath] = incoming.getOrDefault(childPath) + 1

  for index in 1 ..< snapshot.nodes.len:
    if incoming.getOrDefault(snapshot.nodes[index].objectPath) != 1:
      return false

  var visited = initTable[string, bool]()
  var pending = @[atspiRootPath]
  while pending.len > 0:
    let path = pending.pop()
    if visited.hasKey(path):
      return false
    visited[path] = true
    for childPath in snapshot.nodes[indexByPath[path]].childPaths:
      pending.add childPath
  if visited.len != snapshot.nodes.len:
    return false
  true

proc publish(transport: LinuxAtspiTransport; snapshot: AtspiSnapshot;
    changes: seq[AtspiChange]): bool =
  if transport == nil or transport.closed or transport.connection == nil:
    return false
  if not snapshot.validAtspiSnapshot():
    transport.lastError = "Rejected an invalid AT-SPI snapshot"
    return false

  var nextByPath = initTable[string, AtspiNode]()
  for node in snapshot.nodes:
    nextByPath[node.objectPath] = node

  var replaced: seq[(string, AtspiNode)]
  var added: seq[string]
  for node in snapshot.nodes:
    let old = transport.snapshot.nodeAt(node.objectPath)
    let interfaceChanged = old.isSome and
      old.get.interfaceNames() != node.interfaceNames()
    if interfaceChanged:
      replaced.add((node.objectPath, old.get))
      transport.unregisterPath(node.objectPath)
    if old.isNone or interfaceChanged:
      if not transport.registerNode(node):
        for path in added:
          transport.unregisterPath(path)
        for replacement in replaced:
          if not transport.registrations.hasKey(replacement[0]):
            discard transport.registerNode(replacement[1])
        return false
      added.add node.objectPath

  let previous = transport.snapshot
  for oldNode in previous.nodes:
    if not nextByPath.hasKey(oldNode.objectPath):
      transport.unregisterPath(oldNode.objectPath)

  transport.snapshot = snapshot
  transport.nodeIndexByPath.clear()
  for index, node in snapshot.nodes:
    transport.nodeIndexByPath[node.objectPath] = index

  if not transport.embedded and not transport.embed():
    for path in added:
      transport.unregisterPath(path)
    transport.snapshot = previous
    transport.nodeIndexByPath.clear()
    for index, node in previous.nodes:
      transport.nodeIndexByPath[node.objectPath] = index
    return false

  if transport.published:
    transport.emitChanges(previous, changes)
  transport.published = true
  true

proc close*(transport: LinuxAtspiTransport) =
  if transport == nil or transport.closed:
    return
  transport.closed = true
  if transport.connection != nil:
    var paths: seq[string]
    for path in transport.registrations.keys:
      paths.add path
    for path in paths:
      transport.unregisterPath(path)
    var error: ptr GError
    if g_dbus_connection_close_sync(
        transport.connection,
        nil,
        addr error
    ) == 0:
      transport.lastError = error.consumeError()
    g_object_unref(transport.connection)
    transport.connection = nil
  if transport.nodeInfo != nil:
    g_dbus_node_info_unref(transport.nodeInfo)
    transport.nodeInfo = nil
  if transport.context != nil:
    g_main_context_unref(transport.context)
    transport.context = nil

proc connect(transport: LinuxAtspiTransport): bool =
  transport.context = g_main_context_new()
  if transport.context == nil:
    transport.lastError = "Unable to allocate a GLib main context"
    return false
  g_main_context_push_thread_default(transport.context)
  defer:
    g_main_context_pop_thread_default(transport.context)

  var error: ptr GError
  let session = g_bus_get_sync(2, nil, addr error)
  if session == nil:
    transport.lastError = error.consumeError()
    return false
  defer:
    g_object_unref(session)

  let addressReply = g_dbus_connection_call_sync(
    session,
    accessibilityBusName,
    accessibilityBusPath,
    accessibilityBusInterface,
    "GetAddress",
    nil,
    nil,
    0,
    5_000,
    nil,
    addr error
  )
  if addressReply == nil:
    transport.lastError = error.consumeError()
    return false
  defer:
    g_variant_unref(addressReply)
  let addressValue = addressReply.child(0)
  if addressValue == nil:
    transport.lastError = "The accessibility bus returned no address"
    return false
  let address = addressValue.variantString()
  g_variant_unref(addressValue)
  if address.len == 0:
    transport.lastError = "The accessibility bus returned an empty address"
    return false

  transport.connection = g_dbus_connection_new_for_address_sync(
    address.cstring,
    1 or 8,
    nil,
    nil,
    addr error
  )
  if transport.connection == nil:
    transport.lastError = error.consumeError()
    return false
  transport.uniqueName = g_dbus_connection_get_unique_name(
    transport.connection
  ).cstringValue()
  if transport.uniqueName.len == 0:
    transport.lastError = "The accessibility bus assigned no unique name"
    return false

  transport.nodeInfo = g_dbus_node_info_new_for_xml(
    interfaceXml.cstring,
    addr error
  )
  if transport.nodeInfo == nil:
    transport.lastError = error.consumeError()
    return false
  true

proc initLinuxAtspiTransport*(ui: UiRoot;
    options = LinuxAtspiOptions()): LinuxAtspiTransport =
  result = LinuxAtspiTransport(
    ui: ui,
    options: options,
    registrations: initTable[string, seq[uint32]](),
    nodeIndexByPath: initTable[string, int](),
    registryObjectPath: atspiNullPath
  )
  if not result.connect():
    let failure = result.lastError
    result.close()
    result.lastError = failure

proc connected*(transport: LinuxAtspiTransport): bool =
  transport != nil and not transport.closed and transport.connection != nil

proc uniqueBusName*(transport: LinuxAtspiTransport): string =
  if transport == nil: "" else: transport.uniqueName

proc atspiTransport*(transport: LinuxAtspiTransport): AtspiTransport =
  AtspiTransport(
    publish: proc(snapshot: AtspiSnapshot;
        changes: seq[AtspiChange]): bool =
      transport.publish(snapshot, changes)
  )

proc poll*(transport: LinuxAtspiTransport; maxIterations = 32): int =
  if not transport.connected() or transport.context == nil:
    return 0
  while result < max(0, maxIterations) and
      g_main_context_pending(transport.context) != 0:
    if g_main_context_iteration(transport.context, 0) == 0:
      break
    inc result
