"""
Generates the Question 1.1 Logical Layout Diagram of the Hadoop MapReduce Keyword Search Pipeline:
outputs/q1_mapreduce_logical_diagram.png
"""
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as patches

OUT_PATH = Path(__file__).resolve().parents[1] / "outputs" / "q1_mapreduce_logical_diagram.png"

NAVY = "#1B365D"
BLUE = "#2563EB"
TEAL = "#0D9488"
AMBER = "#D97706"
SLATE = "#475569"

fig = plt.figure(figsize=(15.5, 8.2), facecolor="white")
ax = fig.add_axes([0, 0, 1, 1])
ax.set_xlim(0, 1)
ax.set_ylim(0, 1)
ax.axis("off")

# Title banner
ax.add_patch(patches.Rectangle((0, 0.90), 1, 0.10, facecolor=NAVY, edgecolor="none"))
ax.text(0.5, 0.96, "Logical Architecture: Dynamic Case-Insensitive Keyword Search in Hadoop MapReduce",
        fontsize=15.5, fontweight="bold", color="white", ha="center", va="center")
ax.text(0.5, 0.922, "Dynamic Configuration Property: search.keyword = 'africa' (Passed at Runtime via CLI / Configuration)",
        fontsize=10.5, color="#FDE68A", ha="center", va="center")

# Stage headers
stages = [
    (0.03, 0.17, "1. HDFS INPUT & SPLITS\n(LineRecordReader)", NAVY),
    (0.24, 0.21, "2. MAP PHASE\n(KeywordSearchMapper)", BLUE),
    (0.49, 0.21, "3. SHUFFLE & SORT\n(Group by Document Key)", AMBER),
    (0.74, 0.23, "4. REDUCE & HDFS OUTPUT\n(KeywordSearchReducer)", TEAL),
]
for x0, w, label, col in stages:
    ax.add_patch(patches.FancyBboxPatch((x0, 0.805), w, 0.065, boxstyle="round,pad=0.008",
                                        facecolor=col, edgecolor="none"))
    ax.text(x0 + w / 2, 0.838, label, fontsize=9.5, fontweight="bold", color="white", ha="center", va="center")

def draw_box(x, y, w, h, title, body, edge=NAVY, bg="#F8FAFC", title_col=NAVY):
    ax.add_patch(patches.FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.008",
                                        facecolor=bg, edgecolor=edge, linewidth=1.6))
    ax.text(x + 0.01, y + h - 0.024, title, fontsize=8.8, fontweight="bold", color=title_col, va="center")
    ax.text(x + 0.01, y + (h - 0.035) / 2, body, fontsize=8.0, color="#1E293B", va="center", linespacing=1.35)

# Column 1: Input Splits
splits = [
    ("InputSplit 0: doc1.txt", "Row 1: Allan Gray sends ... Africa\nRow 3: The South African ..."),
    ("InputSplit 1: doc2.txt", "Row 1: Ithaca ... South Africa\nRow 33, 58: African Union ..."),
    ("InputSplit 2: doc3.txt", "Row 1, 3, 5, 40-54: South Africa\n9 matches detected"),
    ("InputSplits 3-6: doc4..doc7", "doc5.txt: 5 matches (Rows 1-48)\ndoc4, doc6, doc7: 0 matches"),
]
for idx, (t, b) in enumerate(splits):
    y0 = 0.63 - idx * 0.165
    draw_box(0.03, y0, 0.17, 0.135, t, b, edge=NAVY, bg="#F1F5F9")

# Column 2: Mapper Tasks + Runtime Config
draw_box(0.24, 0.66, 0.21, 0.11, "Configuration Setup()",
         "conf.get('search.keyword')\nCase-insensitive regex pattern\nInit rowCounter = 0 per FileSplit",
         edge=AMBER, bg="#FFFBEB", title_col="#92400E")

mappers = [
    ("Map Task 1 (doc1.txt)", "Emit <'doc1.txt', 'Row=1, Col=64'>\nEmit <'doc1.txt', 'Row=3, Col=11'>\nEmit <'doc1.txt', 'Row=3, Col=95'>"),
    ("Map Task 2 (doc2.txt)", "Emit <'doc2.txt', 'Row=1, Col=57'>\nEmit <'doc2.txt', 'Row=33, Col=24'>\n... (5 total key-value pairs)"),
    ("Map Task 3-7 (doc3..doc7)", "Emit <'doc3.txt', 9 locations>\nEmit <'doc5.txt', 5 locations>\ndoc4, doc6, doc7 -> nothing emitted"),
]
for idx, (t, b) in enumerate(mappers):
    y0 = 0.48 - idx * 0.17
    draw_box(0.24, y0, 0.21, 0.145, t, b, edge=BLUE, bg="#EFF6FF", title_col=BLUE)

# Column 3: Shuffle & Sort
shuffles = [
    ("Group Key: 'doc1.txt'", "Values: [ (R1,C64), (R3,C11), (R3,C95) ]\nPartition -> Reducer 0"),
    ("Group Key: 'doc2.txt'", "Values: [ (R1,C57), (R3,C32),\n  (R33,C24), (R58,C5), (R58,C81) ]"),
    ("Group Key: 'doc3.txt'", "Values: [ (R1,C38), (R3,C7), ... (9 locs) ]\nSorted by Document Key"),
    ("Group Key: 'doc5.txt'", "Values: [ (R1,C62), (R3,C88), ... (5 locs) ]\nNon-matching docs excluded/0"),
]
for idx, (t, b) in enumerate(shuffles):
    y0 = 0.63 - idx * 0.165
    draw_box(0.49, y0, 0.21, 0.135, t, b, edge=AMBER, bg="#FFFBEB", title_col="#B45309")

# Column 4: Reducer & Final Output
draw_box(0.74, 0.56, 0.23, 0.20, "Reducer::reduce(docName, coords)",
         "Iterates through all coordinates\nFormats clean Row & Column list\nComputes total match count per doc\nPreserves 1-based Char & Word Col",
         edge=TEAL, bg="#F0FDFA", title_col=TEAL)

draw_box(0.74, 0.14, 0.23, 0.38, "HDFS Output (part-r-00000)",
         "doc1.txt : 3 matches\n  -> (R1,C64), (R3,C11), (R3,C95)\ndoc2.txt : 5 matches\n  -> (R1,C57)...(R58,C81)\ndoc3.txt : 9 matches\n  -> (R1,C38)...(R54,C44)\ndoc5.txt : 5 matches\n  -> (R1,C62)...(R48,C217)\ndoc4, doc6, doc7 : 0 matches\nTOTAL CORPUS MATCHES = 22",
         edge=NAVY, bg="#F8FAFC", title_col=NAVY)

# Arrows connecting InputSplits directly to their respective Map Tasks
arrow_kw = dict(arrowstyle="-|>,head_width=0.4,head_length=0.6", lw=1.6, color=SLATE)
ax.annotate("", xy=(0.24, 0.56), xytext=(0.20, 0.70), arrowprops=arrow_kw)  # InputSplit 0 -> Map Task 1
ax.annotate("", xy=(0.24, 0.38), xytext=(0.20, 0.53), arrowprops=arrow_kw)  # InputSplit 1 -> Map Task 2
ax.annotate("", xy=(0.24, 0.23), xytext=(0.20, 0.37), arrowprops=arrow_kw)  # InputSplit 2 -> Map Task 3-7
ax.annotate("", xy=(0.24, 0.20), xytext=(0.20, 0.20), arrowprops=arrow_kw)  # InputSplit 3-6 -> Map Task 3-7

# Map Tasks -> Shuffle & Sort
ax.annotate("", xy=(0.49, 0.70), xytext=(0.45, 0.56), arrowprops=arrow_kw)
ax.annotate("", xy=(0.49, 0.53), xytext=(0.45, 0.38), arrowprops=arrow_kw)
ax.annotate("", xy=(0.49, 0.37), xytext=(0.45, 0.24), arrowprops=arrow_kw)
ax.annotate("", xy=(0.49, 0.20), xytext=(0.45, 0.18), arrowprops=arrow_kw)

# Shuffle & Sort -> Reducer
for y_s in [0.70, 0.53, 0.37, 0.20]:
    ax.annotate("", xy=(0.74, 0.66), xytext=(0.70, y_s), arrowprops=arrow_kw)

ax.annotate("", xy=(0.855, 0.52), xytext=(0.855, 0.56), arrowprops=dict(arrowstyle="-|>,head_width=0.5,head_length=0.7", lw=2.0, color=TEAL))

# Bottom note bar (wrapped cleanly inside rounded box)
ax.add_patch(patches.FancyBboxPatch((0.03, 0.025), 0.94, 0.068, boxstyle="round,pad=0.006", facecolor="#F1F5F9", edgecolor="#CBD5E1", linewidth=1))
ax.text(0.5, 0.059,
        "Note: LineRecordReader emits byte offsets as Map keys; therefore KeywordSearchMapper maintains a per-split line counter\n"
        "(currentRowNumber) to emit human-readable 1-based Row numbers alongside 1-based Character and Word Column positions.",
        fontsize=8.6, color=NAVY, ha="center", va="center", fontweight="bold", linespacing=1.35)

fig.savefig(OUT_PATH, dpi=180, bbox_inches="tight", facecolor="white")
plt.close(fig)
print("Saved logical diagram ->", OUT_PATH)
