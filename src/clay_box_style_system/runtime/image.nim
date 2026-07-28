import ../core/node
import ../input/events
import ./ui_root

type
  ImageParams* = object
    source*: string
    width*: float32
    height*: float32
    disabled*: bool

  ImageHandle* = object
    root*: UiRoot
    container*: NodeHandle

proc source*(image: ImageHandle): string =
  image.root.tree.nodes[image.container.id.nodeIndex].imageSource

proc setSource*(image: ImageHandle; source: string) =
  image.root.tree.nodes[image.container.id.nodeIndex].imageSource = source

proc setIntrinsicSize*(image: ImageHandle; width, height: float32) =
  image.root.tree.nodes[image.container.id.nodeIndex].imageWidth = max(0.0'f32, width)
  image.root.tree.nodes[image.container.id.nodeIndex].imageHeight = max(0.0'f32, height)

proc setDisabled*(image: ImageHandle; disabled: bool) =
  image.container.setState(esDisabled, disabled)

proc disabled*(image: ImageHandle): bool =
  esDisabled in image.root.tree.nodes[image.container.id.nodeIndex].states

proc `onLoad=`*(image: ImageHandle; handler: EventHandler) =
  image.container.onLoad = handler

proc `onError=`*(image: ImageHandle; handler: EventHandler) =
  image.container.onError = handler

proc `onClick=`*(image: ImageHandle; handler: EventHandler) =
  image.container.onClick = handler

proc image*(
    root: UiRoot;
    parent: NodeHandle;
    params: ImageParams;
    style = UiStyle();
    id = "";
    groups: openArray[string] = ["image"]
): ImageHandle {.discardable.} =
  result.root = root
  result.container = root.imageNode(
    parent,
    params.source,
    style,
    width = params.width,
    height = params.height,
    id = id,
    groups = groups
  )
  result.setDisabled(params.disabled)

proc image*(
    root: UiRoot;
    params: ImageParams;
    style = UiStyle();
    id = "";
    groups: openArray[string] = ["image"]
): ImageHandle {.discardable.} =
  result.root = root
  result.container = root.imageNode(
    params.source,
    style,
    width = params.width,
    height = params.height,
    id = id,
    groups = groups
  )
  result.setDisabled(params.disabled)

proc image*(
    root: UiRoot;
    parent: NodeHandle;
    source: string;
    width = 0.0'f32;
    height = 0.0'f32;
    disabled = false;
    style = UiStyle();
    id = "";
    groups: openArray[string] = ["image"]
): ImageHandle {.discardable.} =
  root.image(
    parent,
    ImageParams(source: source, width: width, height: height, disabled: disabled),
    style = style,
    id = id,
    groups = groups
  )

proc image*(
    root: UiRoot;
    source: string;
    width = 0.0'f32;
    height = 0.0'f32;
    disabled = false;
    style = UiStyle();
    id = "";
    groups: openArray[string] = ["image"]
): ImageHandle {.discardable.} =
  root.image(
    ImageParams(source: source, width: width, height: height, disabled: disabled),
    style = style,
    id = id,
    groups = groups
  )
