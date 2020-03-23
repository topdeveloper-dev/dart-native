import 'dart:convert';
import 'dart:ffi';

import 'dart:typed_data';

dynamic storeValueToPointer(
    dynamic object, Pointer<Pointer<Void>> ptr) {
  if (object == null) {
    return;
  }
  if (object is num || object is bool) {
    if (object is bool) {
      // TODO: waiting for ffi bool type support.
      object = object ? 1 : 0;
    }
    switch (object) {
      case int :
        ptr.cast<Int32>().value = object;
        break;
    }
  }
}

dynamic loadValueFromPointer(Pointer<Void> ptr, String encoding) {
  dynamic result;
  if (encoding.contains('int') ||
      encoding.contains('float') ||
      encoding == 'bool' ||
      encoding == 'char' ||
      encoding == 'uchar') {
    ByteBuffer buffer = Int64List.fromList([ptr.address]).buffer;
    ByteData data = ByteData.view(buffer);
    switch (encoding) {
      case 'bool':
        result = data.getInt8(0) != 0;
        break;
      case 'char':
          result = utf8.decode([data.getInt8(0)]);
        break;
      case 'uchar':
          result = utf8.decode([data.getUint8(0)]);
        break;
      case 'sint8':
        result = data.getInt8(0);
        break;
      case 'sint16':
        result = data.getInt16(0, Endian.host);
        break;
      case 'sint32':
        result = data.getInt32(0, Endian.host);
        break;
      case 'sint64':
        result = data.getInt64(0, Endian.host);
        break;
      case 'uint8':
        result = data.getUint8(0);
        break;
      case 'uint16':
        result = data.getUint16(0, Endian.host);
        break;
      case 'uint32':
        result = data.getUint32(0, Endian.host);
        break;
      case 'uint64':
        result = data.getUint64(0, Endian.host);
        break;
      case 'float32':
        result = data.getFloat32(0, Endian.host);
        break;
      case 'float64':
        result = data.getFloat64(0, Endian.host);
        break;
      default:
        result = 0;
    }
  }
  return result;
}