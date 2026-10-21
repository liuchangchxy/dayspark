class AttachmentUploadResponse {
  const AttachmentUploadResponse({
    required this.serverFileRef,
    required this.fileSize,
  });

  factory AttachmentUploadResponse.fromJson(Map<String, dynamic> json) {
    final ref = json['serverFileRef'];
    final size = json['fileSize'];
    if (ref is! String || ref.isEmpty) {
      throw const FormatException('invalid field: serverFileRef');
    }
    if (size is! int || size < 0) {
      throw const FormatException('invalid field: fileSize');
    }
    return AttachmentUploadResponse(serverFileRef: ref, fileSize: size);
  }

  final String serverFileRef;
  final int fileSize;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'serverFileRef': serverFileRef,
    'fileSize': fileSize,
  };
}
