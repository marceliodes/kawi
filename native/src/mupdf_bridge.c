#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include "mupdf/fitz.h"

#ifdef _WIN32
#define KAWI_EXPORT __declspec(dllexport)
#else
#define KAWI_EXPORT __attribute__((visibility("default")))
#endif

// --- Multi-threaded Locking ---

static pthread_mutex_t kawi_locks[FZ_LOCK_MAX];
static pthread_once_t kawi_locks_once = PTHREAD_ONCE_INIT;

static void kawi_init_locks(void) {
    int i;
    for (i = 0; i < FZ_LOCK_MAX; i++) {
        pthread_mutex_init(&kawi_locks[i], NULL);
    }
}

static void kawi_lock(void *user, int lock) {
    (void)user;
    if (lock >= 0 && lock < FZ_LOCK_MAX) {
        pthread_mutex_lock(&kawi_locks[lock]);
    }
}

static void kawi_unlock(void *user, int lock) {
    (void)user;
    if (lock >= 0 && lock < FZ_LOCK_MAX) {
        pthread_mutex_unlock(&kawi_locks[lock]);
    }
}

// --- Context Lifecycle ---

KAWI_EXPORT fz_context *kawi_new_context(void) {
    fz_locks_context locks;
    fz_context *ctx = NULL;

    pthread_once(&kawi_locks_once, kawi_init_locks);

    locks.user = NULL;
    locks.lock = kawi_lock;
    locks.unlock = kawi_unlock;

    ctx = fz_new_context(NULL, &locks, FZ_STORE_DEFAULT);
    if (!ctx) {
        return NULL;
    }
    fz_var(ctx);
    fz_try(ctx) {
        fz_register_document_handlers(ctx);
    }
    fz_catch(ctx) {
        fz_drop_context(ctx);
        return NULL;
    }
    return ctx;
}

KAWI_EXPORT fz_context *kawi_clone_context(fz_context *ctx) {
    fz_context *clone = NULL;
    if (!ctx) {
        return NULL;
    }
    fz_var(clone);
    fz_try(ctx) {
        clone = fz_clone_context(ctx);
    }
    fz_catch(ctx) {
        clone = NULL;
    }
    return clone;
}

KAWI_EXPORT void kawi_drop_context(fz_context *ctx) {
    if (ctx) {
        fz_drop_context(ctx);
    }
}

// --- Document Lifecycle ---

KAWI_EXPORT fz_document *kawi_open_document(fz_context *ctx, const char *filename) {
    fz_document *doc = NULL;
    if (!ctx || !filename) {
        return NULL;
    }
    fz_var(doc);
    fz_try(ctx) {
        doc = fz_open_document(ctx, filename);
    }
    fz_catch(ctx) {
        doc = NULL;
    }
    return doc;
}

KAWI_EXPORT void kawi_drop_document(fz_context *ctx, fz_document *doc) {
    if (!ctx || !doc) {
        return;
    }
    fz_try(ctx) {
        fz_drop_document(ctx, doc);
    }
    fz_catch(ctx) {
        // Cleanup failure should not abort
    }
}

KAWI_EXPORT int kawi_count_pages(fz_context *ctx, fz_document *doc) {
    int count = 0;
    if (!ctx || !doc) {
        return 0;
    }
    fz_var(count);
    fz_try(ctx) {
        count = fz_count_pages(ctx, doc);
    }
    fz_catch(ctx) {
        count = 0;
    }
    return count;
}

KAWI_EXPORT int kawi_lookup_metadata(fz_context *ctx, fz_document *doc, const char *key, char *buf, int size) {
    int len = -1;
    if (!ctx || !doc || !key || !buf || size <= 0) {
        return -1;
    }
    fz_var(len);
    fz_try(ctx) {
        len = fz_lookup_metadata(ctx, doc, key, buf, size);
        if (len >= 0 && len < size) {
            buf[len] = '\0';
        } else if (size > 0) {
            buf[size - 1] = '\0';
        }
    }
    fz_catch(ctx) {
        len = -1;
        buf[0] = '\0';
    }
    return len;
}

// --- Rasterization / Cover Extraction ---

KAWI_EXPORT fz_colorspace *kawi_device_rgb(fz_context *ctx) {
    if (!ctx) {
        return NULL;
    }
    return fz_device_rgb(ctx);
}

KAWI_EXPORT fz_pixmap *kawi_new_pixmap_from_page_number(
    fz_context *ctx,
    fz_document *doc,
    int number,
    fz_matrix ctm,
    fz_colorspace *cs,
    int alpha
) {
    fz_pixmap *pix = NULL;
    if (!ctx || !doc) {
        return NULL;
    }
    fz_var(pix);
    fz_try(ctx) {
        pix = fz_new_pixmap_from_page_number(ctx, doc, number, ctm, cs, alpha);
    }
    fz_catch(ctx) {
        pix = NULL;
    }
    return pix;
}

KAWI_EXPORT void kawi_drop_pixmap(fz_context *ctx, fz_pixmap *pix) {
    if (!ctx || !pix) {
        return;
    }
    fz_try(ctx) {
        fz_drop_pixmap(ctx, pix);
    }
    fz_catch(ctx) {
        // Ignored
    }
}

KAWI_EXPORT int kawi_pixmap_width(fz_context *ctx, fz_pixmap *pix) {
    if (!ctx || !pix) {
        return 0;
    }
    return fz_pixmap_width(ctx, pix);
}

KAWI_EXPORT int kawi_pixmap_height(fz_context *ctx, fz_pixmap *pix) {
    if (!ctx || !pix) {
        return 0;
    }
    return fz_pixmap_height(ctx, pix);
}

KAWI_EXPORT unsigned char *kawi_pixmap_samples(fz_context *ctx, fz_pixmap *pix) {
    if (!ctx || !pix) {
        return NULL;
    }
    return fz_pixmap_samples(ctx, pix);
}

// --- Page & Text Extraction ---

KAWI_EXPORT fz_page *kawi_load_page(fz_context *ctx, fz_document *doc, int number) {
    fz_page *page = NULL;
    if (!ctx || !doc) {
        return NULL;
    }
    fz_var(page);
    fz_try(ctx) {
        page = fz_load_page(ctx, doc, number);
    }
    fz_catch(ctx) {
        page = NULL;
    }
    return page;
}

KAWI_EXPORT void kawi_drop_page(fz_context *ctx, fz_page *page) {
    if (!ctx || !page) {
        return;
    }
    fz_try(ctx) {
        fz_drop_page(ctx, page);
    }
    fz_catch(ctx) {
        // Ignored
    }
}

KAWI_EXPORT fz_stext_page *kawi_new_stext_page_from_page(
    fz_context *ctx,
    fz_page *page,
    const fz_stext_options *options
) {
    fz_stext_page *stext = NULL;
    if (!ctx || !page) {
        return NULL;
    }
    fz_var(stext);
    fz_try(ctx) {
        stext = fz_new_stext_page_from_page(ctx, page, options);
    }
    fz_catch(ctx) {
        stext = NULL;
    }
    return stext;
}

KAWI_EXPORT void kawi_drop_stext_page(fz_context *ctx, fz_stext_page *stext) {
    if (!ctx || !stext) {
        return;
    }
    fz_try(ctx) {
        fz_drop_stext_page(ctx, stext);
    }
    fz_catch(ctx) {
        // Ignored
    }
}

KAWI_EXPORT fz_buffer *kawi_new_buffer_from_stext_page(fz_context *ctx, fz_stext_page *stext) {
    fz_buffer *buf = NULL;
    if (!ctx || !stext) {
        return NULL;
    }
    fz_var(buf);
    fz_try(ctx) {
        buf = fz_new_buffer_from_stext_page(ctx, stext);
    }
    fz_catch(ctx) {
        buf = NULL;
    }
    return buf;
}

KAWI_EXPORT void kawi_drop_buffer(fz_context *ctx, fz_buffer *buf) {
    if (!ctx || !buf) {
        return;
    }
    fz_try(ctx) {
        fz_drop_buffer(ctx, buf);
    }
    fz_catch(ctx) {
        // Ignored
    }
}

KAWI_EXPORT const char *kawi_string_from_buffer(fz_context *ctx, fz_buffer *buf) {
    const char *str = "";
    if (!ctx || !buf) {
        return "";
    }
    fz_var(str);
    fz_try(ctx) {
        str = fz_string_from_buffer(ctx, buf);
    }
    fz_catch(ctx) {
        str = "";
    }
    return str ? str : "";
}

// --- Structured Words Extraction ---

typedef struct {
    float x0;
    float y0;
    float x1;
    float y1;
    char text[128];
} kawi_word_t;

KAWI_EXPORT int kawi_extract_words(
    fz_context *ctx,
    fz_stext_page *stext,
    kawi_word_t **out_words
) {
    int count = 0;
    int capacity = 256;
    kawi_word_t *words = NULL;
    fz_stext_block *block = NULL;

    if (!out_words) return 0;
    *out_words = NULL;
    if (!ctx || !stext) return 0;

    fz_var(words);
    fz_var(count);
    fz_var(capacity);
    fz_var(block);

    fz_try(ctx) {
        words = (kawi_word_t *)malloc(capacity * sizeof(kawi_word_t));
        if (!words) {
            fz_throw(ctx, FZ_ERROR_SYSTEM, "Out of memory allocating words array");
        }

        for (block = stext->first_block; block; block = block->next) {
            fz_stext_line *line;
            if (block->type != FZ_STEXT_BLOCK_TEXT) {
                // Safely skip image blocks or non-text blocks
                continue;
            }

            for (line = block->u.t.first_line; line; line = line->next) {
                char current_word[128];
                int word_len = 0;
                float wx0 = 1e9f, wy0 = 1e9f, wx1 = -1e9f, wy1 = -1e9f;
                fz_stext_char *ch;

                for (ch = line->first_char; ch; ch = ch->next) {
                    int c = ch->c;
                    if (c <= 32) {
                        if (word_len > 0) {
                            current_word[word_len] = '\0';
                            if (count >= capacity) {
                                kawi_word_t *new_words;
                                capacity *= 2;
                                new_words = (kawi_word_t *)realloc(words, capacity * sizeof(kawi_word_t));
                                if (!new_words) {
                                    fz_throw(ctx, FZ_ERROR_SYSTEM, "Out of memory expanding words array");
                                }
                                words = new_words;
                            }
                            words[count].x0 = wx0;
                            words[count].y0 = wy0;
                            words[count].x1 = wx1;
                            words[count].y1 = wy1;
                            memcpy(words[count].text, current_word, word_len + 1);
                            count++;

                            word_len = 0;
                            wx0 = wy0 = 1e9f;
                            wx1 = wy1 = -1e9f;
                        }
                    } else {
                        char rune_buf[8];
                        int rune_bytes = fz_runetochar(rune_buf, c);
                        fz_quad q;
                        float qmin_x, qmin_x2, min_x;
                        float qmax_x, qmax_x2, max_x;
                        float qmin_y, qmin_y2, min_y;
                        float qmax_y, qmax_y2, max_y;

                        if (word_len + rune_bytes < 127) {
                            memcpy(current_word + word_len, rune_buf, rune_bytes);
                            word_len += rune_bytes;
                        }

                        q = ch->quad;
                        qmin_x = q.ul.x < q.ll.x ? q.ul.x : q.ll.x;
                        qmin_x2 = q.ur.x < q.lr.x ? q.ur.x : q.lr.x;
                        min_x = qmin_x < qmin_x2 ? qmin_x : qmin_x2;

                        qmax_x = q.ul.x > q.ll.x ? q.ul.x : q.ll.x;
                        qmax_x2 = q.ur.x > q.lr.x ? q.ur.x : q.lr.x;
                        max_x = qmax_x > qmax_x2 ? qmax_x : qmax_x2;

                        qmin_y = q.ul.y < q.ll.y ? q.ul.y : q.ll.y;
                        qmin_y2 = q.ur.y < q.lr.y ? q.ur.y : q.lr.y;
                        min_y = qmin_y < qmin_y2 ? qmin_y : qmin_y2;

                        qmax_y = q.ul.y > q.ll.y ? q.ul.y : q.ll.y;
                        qmax_y2 = q.ur.y > q.lr.y ? q.ur.y : q.lr.y;
                        max_y = qmax_y > qmax_y2 ? qmax_y : qmax_y2;

                        if (min_x < wx0) wx0 = min_x;
                        if (min_y < wy0) wy0 = min_y;
                        if (max_x > wx1) wx1 = max_x;
                        if (max_y > wy1) wy1 = max_y;
                    }
                }

                if (word_len > 0) {
                    current_word[word_len] = '\0';
                    if (count >= capacity) {
                        kawi_word_t *new_words;
                        capacity *= 2;
                        new_words = (kawi_word_t *)realloc(words, capacity * sizeof(kawi_word_t));
                        if (!new_words) {
                            fz_throw(ctx, FZ_ERROR_SYSTEM, "Out of memory expanding words array");
                        }
                        words = new_words;
                    }
                    words[count].x0 = wx0;
                    words[count].y0 = wy0;
                    words[count].x1 = wx1;
                    words[count].y1 = wy1;
                    memcpy(words[count].text, current_word, word_len + 1);
                    count++;
                }
            }
        }
        *out_words = words;
    }
    fz_catch(ctx) {
        if (words) {
            free(words);
        }
        *out_words = NULL;
        count = 0;
    }

    return count;
}

KAWI_EXPORT void kawi_free_words(kawi_word_t *words) {
    if (words) {
        free(words);
    }
}

// --- Outline & Link Navigation ---

KAWI_EXPORT fz_outline *kawi_load_outline(fz_context *ctx, fz_document *doc) {
    fz_outline *outline = NULL;
    if (!ctx || !doc) {
        return NULL;
    }
    fz_var(outline);
    fz_try(ctx) {
        outline = fz_load_outline(ctx, doc);
    }
    fz_catch(ctx) {
        outline = NULL;
    }
    return outline;
}

KAWI_EXPORT void kawi_drop_outline(fz_context *ctx, fz_outline *outline) {
    if (!ctx || !outline) {
        return;
    }
    fz_try(ctx) {
        fz_drop_outline(ctx, outline);
    }
    fz_catch(ctx) {
        // Ignored
    }
}

KAWI_EXPORT const char *kawi_outline_title(fz_outline *outline) {
    if (!outline || !outline->title) return "";
    return outline->title;
}

KAWI_EXPORT const char *kawi_outline_uri(fz_outline *outline) {
    if (!outline || !outline->uri) return "";
    return outline->uri;
}

KAWI_EXPORT fz_outline *kawi_outline_next(fz_outline *outline) {
    if (!outline) return NULL;
    return outline->next;
}

KAWI_EXPORT fz_outline *kawi_outline_down(fz_outline *outline) {
    if (!outline) return NULL;
    return outline->down;
}

KAWI_EXPORT int kawi_outline_page_number(fz_context *ctx, fz_document *doc, fz_outline *outline) {
    int page_num = -1;
    if (!ctx || !doc || !outline) return -1;
    fz_var(page_num);
    fz_try(ctx) {
        fz_location loc = outline->page;
        if ((loc.chapter < 0 || loc.page < 0) && outline->uri) {
            loc = fz_resolve_link(ctx, doc, outline->uri, NULL, NULL);
        }
        if (loc.chapter >= 0 && loc.page >= 0) {
            page_num = fz_page_number_from_location(ctx, doc, loc);
        } else if (loc.page >= 0) {
            page_num = loc.page;
        }
    }
    fz_catch(ctx) {
        page_num = -1;
    }
    return page_num;
}

KAWI_EXPORT fz_location kawi_resolve_link(
    fz_context *ctx,
    fz_document *doc,
    const char *uri,
    float *xp,
    float *yp
) {
    fz_location loc;
    loc.chapter = -1;
    loc.page = -1;
    if (!ctx || !doc || !uri) {
        return loc;
    }
    fz_var(loc);
    fz_try(ctx) {
        loc = fz_resolve_link(ctx, doc, uri, xp, yp);
    }
    fz_catch(ctx) {
        loc.chapter = -1;
        loc.page = -1;
    }
    return loc;
}

KAWI_EXPORT int kawi_page_number_from_location(fz_context *ctx, fz_document *doc, fz_location loc) {
    int page = -1;
    if (!ctx || !doc) {
        return -1;
    }
    fz_var(page);
    fz_try(ctx) {
        page = fz_page_number_from_location(ctx, doc, loc);
    }
    fz_catch(ctx) {
        page = -1;
    }
    return page;
}
