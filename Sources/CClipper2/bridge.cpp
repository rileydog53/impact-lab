// C bridge to Clipper2 for Impact Lab. Clipper2 is by Angus Johnson, Boost Software License 1.0 (vendor/LICENSE).
#include "cclipper2.h"
#include "clipper2/clipper.h"
#include <cstdlib>
#include <cstring>
#include <vector>

using namespace Clipper2Lib;

namespace {

PathsD readPaths(const double *xy, const int32_t *sizes, int32_t count) {
    PathsD paths;
    size_t offset = 0;
    for (int32_t r = 0; r < count; ++r) {
        PathD path;
        for (int32_t i = 0; i < sizes[r]; ++i, offset += 2) path.emplace_back(xy[offset], xy[offset + 1]);
        paths.push_back(std::move(path));
    }
    return paths;
}

struct Ring { PathD path; int32_t piece; bool hole; };

void collect(const PolyPathD &node, std::vector<Ring> &rings, int32_t &pieces) {
    // `node` is an outer ring: it starts a new piece, its children are its holes, and their children are islands.
    int32_t piece = pieces++;
    rings.push_back({node.Polygon(), piece, false});
    for (size_t h = 0; h < node.Count(); ++h) {
        const PolyPathD *hole = node.Child(h);
        rings.push_back({hole->Polygon(), piece, true});
        for (size_t i = 0; i < hole->Count(); ++i) collect(*hole->Child(i), rings, pieces);
    }
}

}

extern "C" int32_t cclipper_boolean(int32_t operation,
                                    const double *subjectXY, const int32_t *subjectSizes, int32_t subjectCount,
                                    const double *clipXY, const int32_t *clipSizes, int32_t clipCount,
                                    int32_t precision, CClipperResult *result) {
    if (!result) return 1;
    std::memset(result, 0, sizeof(CClipperResult));
    ClipType type;
    switch (operation) {
        case CClipperIntersection: type = ClipType::Intersection; break;
        case CClipperUnion: type = ClipType::Union; break;
        case CClipperDifference: type = ClipType::Difference; break;
        case CClipperXor: type = ClipType::Xor; break;
        default: return 2;
    }
    try {
        PolyTreeD tree;
        BooleanOp(type, FillRule::NonZero, readPaths(subjectXY, subjectSizes, subjectCount),
                  readPaths(clipXY, clipSizes, clipCount), tree, precision);
        std::vector<Ring> rings;
        int32_t pieces = 0;
        for (size_t i = 0; i < tree.Count(); ++i) collect(*tree.Child(i), rings, pieces);
        size_t points = 0;
        for (const Ring &ring : rings) points += ring.path.size();
        result->ringCount = static_cast<int32_t>(rings.size());
        result->xy = static_cast<double *>(std::malloc(sizeof(double) * 2 * (points ? points : 1)));
        result->ringSizes = static_cast<int32_t *>(std::malloc(sizeof(int32_t) * (rings.size() ? rings.size() : 1)));
        result->ringPiece = static_cast<int32_t *>(std::malloc(sizeof(int32_t) * (rings.size() ? rings.size() : 1)));
        result->ringIsHole = static_cast<uint8_t *>(std::malloc(rings.size() ? rings.size() : 1));
        size_t offset = 0;
        for (size_t r = 0; r < rings.size(); ++r) {
            result->ringSizes[r] = static_cast<int32_t>(rings[r].path.size());
            result->ringPiece[r] = rings[r].piece;
            result->ringIsHole[r] = rings[r].hole ? 1 : 0;
            for (const PointD &p : rings[r].path) {
                result->xy[offset++] = p.x;
                result->xy[offset++] = p.y;
            }
        }
        return 0;
    } catch (...) {
        cclipper_free(result);
        return 3;
    }
}

extern "C" void cclipper_free(CClipperResult *result) {
    if (!result) return;
    std::free(result->xy);
    std::free(result->ringSizes);
    std::free(result->ringPiece);
    std::free(result->ringIsHole);
    std::memset(result, 0, sizeof(CClipperResult));
}
