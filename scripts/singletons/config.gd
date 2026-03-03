extends Node

@export var webrtcbroker = "vision.lbl.gov"
@export var PCstartupprotocol = "webrtc"
@export var QUESTstartupprotocol = "webrtc"
@export var webrtcroomname = "ascribe"

const CHUNK_SIZE = 500000  # Large chunks to reduce ENet packet count (was 20000)
