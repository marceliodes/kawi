import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'native_loader.dart';

// Opaque types
final class FzContext extends Opaque {}

final class FzDocument extends Opaque {}

final class FzPage extends Opaque {}

final class FzStextPage extends Opaque {}

final class FzBuffer extends Opaque {}

final class FzColorspace extends Opaque {}

final class FzPixmap extends Opaque {}

// Struct types
final class FzLocation extends Struct {
  @Int32()
  external int chapter;
  @Int32()
  external int page;
}

final class FzOutline extends Struct {
  @Int32()
  external int refs;
  @Int32()
  external int pad0;
  external Pointer<Utf8> title;
  external Pointer<Utf8> uri;
  external FzLocation page;
  @Float()
  external double x;
  @Float()
  external double y;
  external Pointer<FzOutline> next;
  external Pointer<FzOutline> down;
  @Int32()
  external int isOpen;
  @Int32()
  external int pad1;
}

final class FzPoint extends Struct {
  @Float()
  external double x;
  @Float()
  external double y;
}

final class FzRect extends Struct {
  @Float()
  external double x0;
  @Float()
  external double y0;
  @Float()
  external double x1;
  @Float()
  external double y1;
}

final class FzMatrix extends Struct {
  @Float()
  external double a;
  @Float()
  external double b;
  @Float()
  external double c;
  @Float()
  external double d;
  @Float()
  external double e;
  @Float()
  external double f;

  static void setIdentity(Pointer<FzMatrix> m) {
    m.ref.a = 1.0;
    m.ref.b = 0.0;
    m.ref.c = 0.0;
    m.ref.d = 1.0;
    m.ref.e = 0.0;
    m.ref.f = 0.0;
  }
}

final class FzQuad extends Struct {
  external FzPoint ul;
  external FzPoint ur;
  external FzPoint ll;
  external FzPoint lr;
}

final class KawiWord extends Struct {
  @Float()
  external double x0;
  @Float()
  external double y0;
  @Float()
  external double x1;
  @Float()
  external double y1;
  @Array(128)
  external Array<Uint8> text;

  String get wordString {
    final list = <int>[];
    for (var i = 0; i < 128; i++) {
      final byte = text[i];
      if (byte == 0) break;
      list.add(byte);
    }
    return String.fromCharCodes(list);
  }
}

class MuPdfBindings {
  MuPdfBindings._(this._dylib) {
    _init();
  }

  static MuPdfBindings? _instance;
  static MuPdfBindings get instance =>
      _instance ??= MuPdfBindings._(loadNativeLibrary('mupdf'));

  // Allow passing custom DynamicLibrary for testing
  factory MuPdfBindings.fromLibrary(DynamicLibrary dylib) =>
      MuPdfBindings._(dylib);

  final DynamicLibrary _dylib;

  // Exact version pinned to 1.24.10
  static const String fzVersion = '1.24.10';

  // Context management
  late final Pointer<FzContext> Function(
    Pointer<Void> alloc,
    Pointer<Void> locks,
    int maxStore,
    Pointer<Utf8> version,
  )
  fzNewContextImp;

  late final void Function(Pointer<FzContext> ctx) fzDropContext;
  late final void Function(Pointer<FzContext> ctx) fzRegisterDocumentHandlers;

  // Document management
  late final Pointer<FzDocument> Function(
    Pointer<FzContext> ctx,
    Pointer<Utf8> filename,
  )
  fzOpenDocument;

  late final void Function(Pointer<FzContext> ctx, Pointer<FzDocument> doc)
  fzDropDocument;

  late final int Function(Pointer<FzContext> ctx, Pointer<FzDocument> doc)
  fzCountPages;

  late final int Function(
    Pointer<FzContext> ctx,
    Pointer<FzDocument> doc,
    Pointer<Utf8> key,
    Pointer<Utf8> buf,
    int size,
  )
  fzLookupMetadata;

  // Outline / TOC
  late final Pointer<FzOutline> Function(
    Pointer<FzContext> ctx,
    Pointer<FzDocument> doc,
  )
  fzLoadOutline;

  late final void Function(Pointer<FzContext> ctx, Pointer<FzOutline> outline)
  fzDropOutline;

  late final FzLocation Function(
    Pointer<FzContext> ctx,
    Pointer<FzDocument> doc,
    Pointer<Utf8> uri,
    Pointer<Float> xp,
    Pointer<Float> yp,
  )
  fzResolveLink;

  late final int Function(
    Pointer<FzContext> ctx,
    Pointer<FzDocument> doc,
    FzLocation loc,
  )
  fzPageNumberFromLocation;

  // Page management
  late final Pointer<FzPage> Function(
    Pointer<FzContext> ctx,
    Pointer<FzDocument> doc,
    int number,
  )
  fzLoadPage;

  late final void Function(Pointer<FzContext> ctx, Pointer<FzPage> page)
  fzDropPage;

  // Structured text
  late final Pointer<FzStextPage> Function(
    Pointer<FzContext> ctx,
    Pointer<FzPage> page,
    Pointer<Void> options,
  )
  fzNewStextPageFromPage;

  late final void Function(Pointer<FzContext> ctx, Pointer<FzStextPage> page)
  fzDropStextPage;

  late final Pointer<FzBuffer> Function(
    Pointer<FzContext> ctx,
    Pointer<FzStextPage> text,
  )
  fzNewBufferFromStextPage;

  late final Pointer<Utf8> Function(
    Pointer<FzContext> ctx,
    Pointer<FzBuffer> buf,
  )
  fzStringFromBuffer;

  late final void Function(Pointer<FzContext> ctx, Pointer<FzBuffer> buf)
  fzDropBuffer;

  // Pixmap / rasterization for cover
  late final Pointer<FzPixmap> Function(
    Pointer<FzContext> ctx,
    Pointer<FzDocument> doc,
    int number,
    FzMatrix ctm,
    Pointer<FzColorspace> cs,
    int alpha,
  )
  fzNewPixmapFromPageNumber;

  late final void Function(Pointer<FzContext> ctx, Pointer<FzPixmap> pix)
  fzDropPixmap;

  late final Pointer<FzColorspace> Function(Pointer<FzContext> ctx) fzDeviceRgb;

  late final int Function(Pointer<FzContext> ctx, Pointer<FzPixmap> pix)
  fzPixmapWidth;

  late final int Function(Pointer<FzContext> ctx, Pointer<FzPixmap> pix)
  fzPixmapHeight;

  late final Pointer<Uint8> Function(
    Pointer<FzContext> ctx,
    Pointer<FzPixmap> pix,
  )
  fzPixmapSamples;

  late final Pointer<FzContext> Function(Pointer<FzContext> ctx) cloneContext;

  late final int Function(
    Pointer<FzContext> ctx,
    Pointer<FzStextPage> stext,
    Pointer<Pointer<KawiWord>> outWords,
  )
  kawiExtractWords;

  late final void Function(Pointer<KawiWord> words) kawiFreeWords;

  late final Pointer<Utf8> Function(Pointer<FzOutline> outline)
  kawiOutlineTitle;

  late final Pointer<Utf8> Function(Pointer<FzOutline> outline) kawiOutlineUri;

  late final Pointer<FzOutline> Function(Pointer<FzOutline> outline)
  kawiOutlineNext;

  late final Pointer<FzOutline> Function(Pointer<FzOutline> outline)
  kawiOutlineDown;

  late final int Function(
    Pointer<FzContext> ctx,
    Pointer<FzDocument> doc,
    Pointer<FzOutline> outline,
  )
  kawiOutlinePageNumber;

  bool _hasKawiBridge = false;
  late final Pointer<FzContext> Function() _kawiNewContext;
  late final void Function(Pointer<FzContext> ctx) _kawiDropContext;

  void _init() {
    String sym(String kawiName, String fzName) =>
        _dylib.providesSymbol(kawiName) ? kawiName : fzName;

    _hasKawiBridge = _dylib.providesSymbol('kawi_new_context');
    if (_hasKawiBridge) {
      _kawiNewContext = _dylib
          .lookup<NativeFunction<Pointer<FzContext> Function()>>(
            'kawi_new_context',
          )
          .asFunction();
      _kawiDropContext = _dylib
          .lookup<NativeFunction<Void Function(Pointer<FzContext>)>>(
            'kawi_drop_context',
          )
          .asFunction();
    }

    if (_dylib.providesSymbol('fz_new_context_imp')) {
      fzNewContextImp = _dylib
          .lookup<
            NativeFunction<
              Pointer<FzContext> Function(
                Pointer<Void>,
                Pointer<Void>,
                IntPtr,
                Pointer<Utf8>,
              )
            >
          >('fz_new_context_imp')
          .asFunction();
    }

    if (_dylib.providesSymbol('fz_register_document_handlers')) {
      fzRegisterDocumentHandlers = _dylib
          .lookup<NativeFunction<Void Function(Pointer<FzContext>)>>(
            'fz_register_document_handlers',
          )
          .asFunction();
    }

    fzDropContext = _dylib
        .lookup<NativeFunction<Void Function(Pointer<FzContext>)>>(
          sym('kawi_drop_context', 'fz_drop_context'),
        )
        .asFunction();

    fzOpenDocument = _dylib
        .lookup<
          NativeFunction<
            Pointer<FzDocument> Function(Pointer<FzContext>, Pointer<Utf8>)
          >
        >(sym('kawi_open_document', 'fz_open_document'))
        .asFunction();

    fzDropDocument = _dylib
        .lookup<
          NativeFunction<Void Function(Pointer<FzContext>, Pointer<FzDocument>)>
        >(sym('kawi_drop_document', 'fz_drop_document'))
        .asFunction();

    fzCountPages = _dylib
        .lookup<
          NativeFunction<
            Int32 Function(Pointer<FzContext>, Pointer<FzDocument>)
          >
        >(sym('kawi_count_pages', 'fz_count_pages'))
        .asFunction();

    fzLookupMetadata = _dylib
        .lookup<
          NativeFunction<
            Int32 Function(
              Pointer<FzContext>,
              Pointer<FzDocument>,
              Pointer<Utf8>,
              Pointer<Utf8>,
              Int32,
            )
          >
        >(sym('kawi_lookup_metadata', 'fz_lookup_metadata'))
        .asFunction();

    fzLoadOutline = _dylib
        .lookup<
          NativeFunction<
            Pointer<FzOutline> Function(Pointer<FzContext>, Pointer<FzDocument>)
          >
        >(sym('kawi_load_outline', 'fz_load_outline'))
        .asFunction();

    fzDropOutline = _dylib
        .lookup<
          NativeFunction<Void Function(Pointer<FzContext>, Pointer<FzOutline>)>
        >(sym('kawi_drop_outline', 'fz_drop_outline'))
        .asFunction();

    fzResolveLink = _dylib
        .lookup<
          NativeFunction<
            FzLocation Function(
              Pointer<FzContext>,
              Pointer<FzDocument>,
              Pointer<Utf8>,
              Pointer<Float>,
              Pointer<Float>,
            )
          >
        >(sym('kawi_resolve_link', 'fz_resolve_link'))
        .asFunction();

    fzPageNumberFromLocation = _dylib
        .lookup<
          NativeFunction<
            Int32 Function(Pointer<FzContext>, Pointer<FzDocument>, FzLocation)
          >
        >(sym('kawi_page_number_from_location', 'fz_page_number_from_location'))
        .asFunction();

    fzLoadPage = _dylib
        .lookup<
          NativeFunction<
            Pointer<FzPage> Function(
              Pointer<FzContext>,
              Pointer<FzDocument>,
              Int32,
            )
          >
        >(sym('kawi_load_page', 'fz_load_page'))
        .asFunction();

    fzDropPage = _dylib
        .lookup<
          NativeFunction<Void Function(Pointer<FzContext>, Pointer<FzPage>)>
        >(sym('kawi_drop_page', 'fz_drop_page'))
        .asFunction();

    fzNewStextPageFromPage = _dylib
        .lookup<
          NativeFunction<
            Pointer<FzStextPage> Function(
              Pointer<FzContext>,
              Pointer<FzPage>,
              Pointer<Void>,
            )
          >
        >(sym('kawi_new_stext_page_from_page', 'fz_new_stext_page_from_page'))
        .asFunction();

    fzDropStextPage = _dylib
        .lookup<
          NativeFunction<
            Void Function(Pointer<FzContext>, Pointer<FzStextPage>)
          >
        >(sym('kawi_drop_stext_page', 'fz_drop_stext_page'))
        .asFunction();

    fzNewBufferFromStextPage = _dylib
        .lookup<
          NativeFunction<
            Pointer<FzBuffer> Function(Pointer<FzContext>, Pointer<FzStextPage>)
          >
        >(
          sym(
            'kawi_new_buffer_from_stext_page',
            'fz_new_buffer_from_stext_page',
          ),
        )
        .asFunction();

    fzStringFromBuffer = _dylib
        .lookup<
          NativeFunction<
            Pointer<Utf8> Function(Pointer<FzContext>, Pointer<FzBuffer>)
          >
        >(sym('kawi_string_from_buffer', 'fz_string_from_buffer'))
        .asFunction();

    fzDropBuffer = _dylib
        .lookup<
          NativeFunction<Void Function(Pointer<FzContext>, Pointer<FzBuffer>)>
        >(sym('kawi_drop_buffer', 'fz_drop_buffer'))
        .asFunction();

    fzNewPixmapFromPageNumber = _dylib
        .lookup<
          NativeFunction<
            Pointer<FzPixmap> Function(
              Pointer<FzContext>,
              Pointer<FzDocument>,
              Int32,
              FzMatrix,
              Pointer<FzColorspace>,
              Int32,
            )
          >
        >(
          sym(
            'kawi_new_pixmap_from_page_number',
            'fz_new_pixmap_from_page_number',
          ),
        )
        .asFunction();

    fzDropPixmap = _dylib
        .lookup<
          NativeFunction<Void Function(Pointer<FzContext>, Pointer<FzPixmap>)>
        >(sym('kawi_drop_pixmap', 'fz_drop_pixmap'))
        .asFunction();

    fzDeviceRgb = _dylib
        .lookup<
          NativeFunction<Pointer<FzColorspace> Function(Pointer<FzContext>)>
        >(sym('kawi_device_rgb', 'fz_device_rgb'))
        .asFunction();

    fzPixmapWidth = _dylib
        .lookup<
          NativeFunction<Int32 Function(Pointer<FzContext>, Pointer<FzPixmap>)>
        >(sym('kawi_pixmap_width', 'fz_pixmap_width'))
        .asFunction();

    fzPixmapHeight = _dylib
        .lookup<
          NativeFunction<Int32 Function(Pointer<FzContext>, Pointer<FzPixmap>)>
        >(sym('kawi_pixmap_height', 'fz_pixmap_height'))
        .asFunction();

    fzPixmapSamples = _dylib
        .lookup<
          NativeFunction<
            Pointer<Uint8> Function(Pointer<FzContext>, Pointer<FzPixmap>)
          >
        >(sym('kawi_pixmap_samples', 'fz_pixmap_samples'))
        .asFunction();

    if (_dylib.providesSymbol('kawi_clone_context')) {
      cloneContext = _dylib
          .lookup<
            NativeFunction<Pointer<FzContext> Function(Pointer<FzContext>)>
          >('kawi_clone_context')
          .asFunction();
    } else {
      cloneContext = _dylib
          .lookup<
            NativeFunction<Pointer<FzContext> Function(Pointer<FzContext>)>
          >('fz_clone_context')
          .asFunction();
    }

    if (_dylib.providesSymbol('kawi_extract_words')) {
      kawiExtractWords = _dylib
          .lookup<
            NativeFunction<
              Int32 Function(
                Pointer<FzContext>,
                Pointer<FzStextPage>,
                Pointer<Pointer<KawiWord>>,
              )
            >
          >('kawi_extract_words')
          .asFunction();

      kawiFreeWords = _dylib
          .lookup<NativeFunction<Void Function(Pointer<KawiWord>)>>(
            'kawi_free_words',
          )
          .asFunction();
    }

    if (_dylib.providesSymbol('kawi_outline_title')) {
      kawiOutlineTitle = _dylib
          .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<FzOutline>)>>(
            'kawi_outline_title',
          )
          .asFunction();

      kawiOutlineUri = _dylib
          .lookup<NativeFunction<Pointer<Utf8> Function(Pointer<FzOutline>)>>(
            'kawi_outline_uri',
          )
          .asFunction();

      kawiOutlineNext = _dylib
          .lookup<
            NativeFunction<Pointer<FzOutline> Function(Pointer<FzOutline>)>
          >('kawi_outline_next')
          .asFunction();

      kawiOutlineDown = _dylib
          .lookup<
            NativeFunction<Pointer<FzOutline> Function(Pointer<FzOutline>)>
          >('kawi_outline_down')
          .asFunction();

      kawiOutlinePageNumber = _dylib
          .lookup<
            NativeFunction<
              Int32 Function(
                Pointer<FzContext>,
                Pointer<FzDocument>,
                Pointer<FzOutline>,
              )
            >
          >('kawi_outline_page_number')
          .asFunction();
    }
  }

  /// Creates a newly initialized [FzContext] with all document handlers registered.
  /// Must be freed using [dropContext].
  Pointer<FzContext> createContext() {
    if (_hasKawiBridge) {
      final ctx = _kawiNewContext();
      if (ctx == nullptr) {
        throw StateError('Failed to initialize MuPDF context');
      }
      return ctx;
    }

    final versionPtr = fzVersion.toNativeUtf8();
    try {
      final ctx = fzNewContextImp(nullptr, nullptr, 0, versionPtr);
      if (ctx == nullptr) {
        throw StateError('Failed to initialize MuPDF context');
      }
      fzRegisterDocumentHandlers(ctx);
      return ctx;
    } finally {
      calloc.free(versionPtr);
    }
  }

  void dropContext(Pointer<FzContext> ctx) {
    if (ctx != nullptr) {
      if (_hasKawiBridge) {
        _kawiDropContext(ctx);
      } else {
        fzDropContext(ctx);
      }
    }
  }
}
