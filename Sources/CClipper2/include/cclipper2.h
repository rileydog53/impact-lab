// A small C interface to Clipper2 (Angus Johnson, Boost Software License 1.0, see vendor/LICENSE),
// so Swift can call polygon booleans without C++ interoperability.
#ifndef CCLIPPER2_H
#define CCLIPPER2_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    CClipperIntersection = 1,
    CClipperUnion = 2,
    CClipperDifference = 3,
    CClipperXor = 4
} CClipperOperation;

/// Output rings grouped into connected pieces. Ring i has ringSizes[i] points (x, y pairs in `xy`),
/// belongs to piece ringPiece[i], and is a hole when ringIsHole[i] is 1. Each piece starts with its outer ring.
typedef struct {
    double *xy;
    int32_t *ringSizes;
    int32_t *ringPiece;
    uint8_t *ringIsHole;
    int32_t ringCount;
} CClipperResult;

/// Boolean operation with the non-zero fill rule. Rings are flat x, y arrays; `precision` is the number of
/// decimal places kept (Clipper2 accepts -8...8). Returns 0 on success; free the result with cclipper_free.
int32_t cclipper_boolean(int32_t operation,
                         const double *subjectXY, const int32_t *subjectSizes, int32_t subjectCount,
                         const double *clipXY, const int32_t *clipSizes, int32_t clipCount,
                         int32_t precision, CClipperResult *result);

void cclipper_free(CClipperResult *result);

#ifdef __cplusplus
}
#endif

#endif
