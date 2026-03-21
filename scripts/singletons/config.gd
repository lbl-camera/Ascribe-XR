extends Node

@export var webrtcbroker = "vision.lbl.gov"
@export var PCstartupprotocol = "webrtc"
@export var QUESTstartupprotocol = "webrtc"
@export var webrtcroomname = "ascribe"

## Ascribe-Link HTTP server URL
## Use 127.0.0.1 instead of localhost to avoid IPv6 issues on Windows
@export var ascribe_link_url = "http://127.0.0.1:8000"

const CHUNK_SIZE = 20000
