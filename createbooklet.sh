#!/bin/bash

# Default values
LANGUAGES=""

# --- GLOBAL CONFIGURATION VARIABLES ---
# Define the size of a SINGLE content page (after mutool poster has split it)
# This is the original size of your individual booklet pages.
# Format: "WIDTHin,HEIGHTin" (e.g., "8.125in,10.25in" if your original multi-page PDF was 16.25in wide)
SINGLE_PAGE_DIMENSIONS_INCHES="8.125in,10.25in"

# Define the physical paper sheet size you will print the booklet on (for pdfjam's imposition).
# This is the large sheet that pdfjam arranges two booklet pages onto.
BOOKLET_PRINT_SHEET_SIZE="{16.25in,10.25in}" # Format: "{WIDTHin,HEIGHTin}" or "a4paper", "letterpaper" etc.

# Define the final output paper size for the crop marks document.
# This will always be A4 as per your requirement.
FINAL_OUTPUT_PAPER_SIZE="a4" # a0, a1, a2, a3, a4, a5, a6, b0, b1, b2, b3, b4, b5, b6, letter, legal, executive

# Rotation for the imposed booklet PDF (from pdfjam) before adding crop marks.
# Use 'east' for 90 degrees clockwise, 'west' for 90 degrees counter-clockwise,
# 'south' for 180 degrees, or '' for no rotation.
#BOOKLET_FINAL_ROTATION="east" # Adjust as needed based on pdfjam's output orientation
BOOKLET_FINAL_ROTATION=""

# --- NEW: Margin for Final Output (Crop Marks) ---
# Define the margin to be applied to the final A4 output for content and crop marks.
# This ensures crop marks and content are inside the paper area.
# 1 inch = 72 points. Adjust as needed.
MARGIN_INCHES="0.25" # 1 inch margin on all sides for the final A4 output

# --- END GLOBAL CONFIGURATION ---

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --lang=*)
            LANGUAGES="${1#*=}" # Extract the value after '='
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if languages were provided
if [[ -z "$LANGUAGES" ]]; then
    echo "Usage: $0 --lang=<lang1,lang2,...>"
    exit 1
fi

echo "Selected languages: $LANGUAGES"

IFS=',' read -r -a lang_array <<< "$LANGUAGES"

# Extract width and height from SINGLE_PAGE_DIMENSIONS_INCHES for Ghostscript
_SINGLE_PAGE_WIDTH_IN=$(echo "$SINGLE_PAGE_DIMENSIONS_INCHES" | cut -d',' -f1 | sed 's/in//')
_SINGLE_PAGE_HEIGHT_IN=$(echo "$SINGLE_PAGE_DIMENSIONS_INCHES" | cut -d',' -f2 | sed 's/in//')

# Convert inches to points (1 inch = 72 points) for blank page generation
BLANK_PAGE_WIDTH_PTS=$(awk "BEGIN {print $_SINGLE_PAGE_WIDTH_IN * 72}")
BLANK_PAGE_HEIGHT_PTS=$(awk "BEGIN {print $_SINGLE_PAGE_HEIGHT_IN * 72}")

# Define A4 dimensions in points for LaTeX scaling calculations
A4_WIDTH_PT="595.28"  # A4 portrait width in points
A4_HEIGHT_PT="841.89" # A4 portrait height in points

# --- NEW: Calculate Effective A4 Dimensions with Margin ---
MARGIN_PT=$(awk "BEGIN {print $MARGIN_INCHES * 72}")
EFFECTIVE_A4_WIDTH_PT=$(awk "BEGIN {print $A4_WIDTH_PT - (2 * $MARGIN_PT)}")
EFFECTIVE_A4_HEIGHT_PT=$(awk "BEGIN {print $A4_HEIGHT_PT - (2 * $MARGIN_PT)}")

echo "Margin (in): $MARGIN_INCHES, Margin (pt): $MARGIN_PT"
echo "Effective A4 Content Area (Width x Height in pt): ${EFFECTIVE_A4_WIDTH_PT} x ${EFFECTIVE_A4_HEIGHT_PT}"

# Create a single temporary directory for the entire script run
TEMP_DIR=$(mktemp -d)

cleanup() {
    echo "Cleaning up temporary directory: $TEMP_DIR"
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT SIGHUP SIGINT SIGTERM

echo "Working in temporary directory: $TEMP_DIR"

for lang in "${lang_array[@]}"; do
    echo "Processing language: $lang"

    # --- SVG to PDF Conversion ---
    for file in svg_pages/pipoca-escola*"_${lang}.svg"; do
        if [[ -e "$file" ]]; then
            filename=$(basename "$file")
            outname="${filename%.svg}.pdf"
            echo "Converting $file to $TEMP_DIR/$outname"
            inkscape --export-filename="$TEMP_DIR/$outname" "$file"
            if [ $? -ne 0 ]; then
                echo "Error: Inkscape failed for $file."
                continue
            fi
        else
            echo "Warning: SVG file not found for $lang: $file"
        fi
    done

    # --- Concatenate PDFs (book_pipoca.pdf - still has 2 pages per sheet) ---
    INPUT_PDF_GLOB="$TEMP_DIR/pipoca-escola"*"_${lang}.pdf"
    OUTPUT_BOOK_PDF="$TEMP_DIR/book_pipoca_${lang}.pdf"

    shopt -s nullglob
    FILES_TO_MERGE=( $INPUT_PDF_GLOB )
    shopt -u nullglob

    if [ ${#FILES_TO_MERGE[@]} -eq 0 ]; then
        echo "Error: No PDF files found for $lang matching pattern: $INPUT_PDF_GLOB"
        continue
    else
        echo "Merging files for $lang: ${FILES_TO_MERGE[@]}"
        pdftk "${FILES_TO_MERGE[@]}" cat output "$OUTPUT_BOOK_PDF"
        if [ $? -eq 0 ]; then
            echo "PDFs for $lang successfully combined into $OUTPUT_BOOK_PDF"
        else
            echo "Error: pdftk failed to combine PDFs for $lang."
            continue
        fi
    fi

    # --- Create Ebook Version (uses OUTPUT_BOOK_PDF directly) ---
    EBOOK_FINAL_OUTPUT="ebook_pipoca_${lang}.pdf"
    echo "Creating ebook version for $lang: $EBOOK_FINAL_OUTPUT"
    gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook -dNOPAUSE -dBATCH -sOutputFile="$EBOOK_FINAL_OUTPUT" "$OUTPUT_BOOK_PDF"
    if [ $? -eq 0 ]; then
        echo "Ebook for $lang created: $EBOOK_FINAL_OUTPUT"
    else
        echo "Error: Ghostscript failed to create ebook for $lang."
    fi

    # --- Prepare for Booklet: Split Pages with mutool poster ---
    BOOKLET_TEMP_INPUT="$TEMP_DIR/book_pipoca_split_temp_${lang}.pdf" # Output from mutool poster
    if [ -f "$OUTPUT_BOOK_PDF" ]; then
        echo "Splitting pages for booklet for $lang using mutool poster..."
        mutool poster -x 2 "$OUTPUT_BOOK_PDF" "$BOOKLET_TEMP_INPUT"
        if [ $? -ne 0 ]; then
            echo "Error: mutool poster failed to split pages for booklet for $lang."
            continue
        fi
        echo "Pages for $lang successfully split for booklet: $BOOKLET_TEMP_INPUT"
    else
        echo "Warning: Combined PDF ($OUTPUT_BOOK_PDF) not found for $lang, skipping page splitting."
        continue
    fi

    # --- Extract Front Cover, Back Cover, and Content from mutool output ---
    FRONT_COVER_PDF="$TEMP_DIR/front_cover_${lang}.pdf"
    BACK_COVER_PDF="$TEMP_DIR/back_cover_${lang}.pdf"
    BOOK_CONTENT_PDF="$TEMP_DIR/book_content_${lang}.pdf"

    if [ -f "$BOOKLET_TEMP_INPUT" ]; then
        TOTAL_PAGES_MUTOOL=$(pdfinfo "$BOOKLET_TEMP_INPUT" | grep "Pages:" | awk '{print $2}')
        if [ "$TOTAL_PAGES_MUTOOL" -lt 3 ]; then
            echo "Error: Not enough pages in mutool output for cover/content separation ($TOTAL_PAGES_MUTOOL pages found). Expected at least 3 (Back Cover, Front Cover, 1 content page)."
            continue
        fi

        echo "Extracting covers and content for $lang..."
        # Page 1 of mutool output is Back Cover
        if ! pdftk "$BOOKLET_TEMP_INPUT" cat 1 output "$BACK_COVER_PDF"; then
            echo "Error: Failed to extract back cover."
            continue
        fi
        # Page 2 of mutool output is Front Cover
        if ! pdftk "$BOOKLET_TEMP_INPUT" cat 2 output "$FRONT_COVER_PDF"; then
            echo "Error: Failed to extract front cover."
            continue
        fi
        # Pages 3-end of mutool output are Book Content
        if ! pdftk "$BOOKLET_TEMP_INPUT" cat 3-end output "$BOOK_CONTENT_PDF"; then
            echo "Error: Failed to extract book content."
            continue
        fi
    else
        echo "Error: Mutool output ($BOOKLET_TEMP_INPUT) not found, cannot extract covers/content."
        continue
    fi

    # --- Calculate and Add Blank Pages between Content and Back Cover ---
    # The padding needs to ensure that (TOTAL_CONTENT_PAGES + 1 for back cover + 1 for front cover) is a multiple of 4.

    CONTENT_ONLY_PAGES=$(pdfinfo "$BOOK_CONTENT_PDF" | grep "Pages:" | awk '{print $2}')

    # Total pages for pdfjam to impose will be (Front Cover (1) + ContentPages + Blank Pages + Back Cover (1)).
    # We need (1 + CONTENT_ONLY_PAGES + PAGES_TO_ADD + 1) to be a multiple of 4.
    # So, (CONTENT_ONLY_PAGES + 2) + PAGES_TO_ADD must be a multiple of 4.
    PAGES_TO_ADD=$(( (4 - ((CONTENT_ONLY_PAGES + 2) % 4)) % 4 ))

    # Ensure a blank page can be created
    BLANK_PDF_PAGE="$TEMP_DIR/blank_page.pdf"
    if [ ! -f "$BLANK_PDF_PAGE" ]; then # Create it only if it doesn't exist for the first time
        echo "Creating blank PDF page with dimensions: ${BLANK_PAGE_WIDTH_PTS}pts x ${BLANK_PAGE_HEIGHT_PTS}pts"
        gs -sDEVICE=pdfwrite -o "$BLANK_PDF_PAGE" \
           -dDEVICEWIDTHPOINTS="$BLANK_PAGE_WIDTH_PTS" \
           -dDEVICEHEIGHTPOINTS="$BLANK_PAGE_HEIGHT_PTS" \
           -dNOPAUSE -dBATCH -dSAFER -c "showpage" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error: Failed to create blank PDF page with correct dimensions."
            continue
        fi
    fi

    BLANKS_FOR_PDFTK=""
    if [ "$PAGES_TO_ADD" -gt 0 ]; then
        echo "Adding $PAGES_TO_ADD blank page(s) between content and back cover for $lang..."
        for i in $(seq 1 $PAGES_TO_ADD); do
            BLANKS_FOR_PDFTK+=" $BLANK_PDF_PAGE"
        done
    else
        echo "No blank pages needed for $lang for content+covers."
    fi

    # --- Assemble final booklet input for pdfjam ---
    BOOKLET_INPUT_PDFJAM="$TEMP_DIR/book_pipoca_for_pdfjam_${lang}.pdf"

    # The order is: Front Cover, Book Content, (Blank Pages if needed), Back Cover
    # Use the extracted files directly. This is the correct pdftk syntax.
    if pdftk "$FRONT_COVER_PDF" "$BOOK_CONTENT_PDF" $BLANKS_FOR_PDFTK "$BACK_COVER_PDF" cat output "$BOOKLET_INPUT_PDFJAM"; then
        echo "Booklet input for pdfjam assembled: $BOOKLET_INPUT_PDFJAM"
    else
        echo "Error: pdftk failed to assemble booklet input for $lang."
        continue
    fi

    # --- Create Booklet Version (uses the reordered and padded PDF as input) ---
    BOOKLET_PRE_CROP_PDF="$TEMP_DIR/booklet_pipoca_print_uncropped_${lang}.pdf" # Temp name for pdfjam output
    BOOKLET_TO_CROP_PDF="$TEMP_DIR/booklet_pipoca_print_rotated_${lang}.pdf" # Temp name after optional rotation

    if [ -f "$BOOKLET_INPUT_PDFJAM" ]; then
        echo "Creating booklet for $lang using pdfjam..."
        pdfjam --booklet true \
               --papersize "${BOOKLET_PRINT_SHEET_SIZE}" \
               --outfile "$BOOKLET_PRE_CROP_PDF" \
               "$BOOKLET_INPUT_PDFJAM" \
               --quiet
        if [ $? -eq 0 ]; then
            echo "Booklet for $lang created (pre-rotation): $BOOKLET_PRE_CROP_PDF"
        else
            echo "Error: pdfjam failed to create booklet for $lang."
            rm -f "$BOOKLET_PRE_CROP_PDF"
            continue
        fi
    else
        echo "Warning: Booklet input PDF ($BOOKLET_INPUT_PDFJAM) not found for $lang, skipping booklet creation."
        continue
    fi

    # --- OPTIONAL: Rotate BOOKLET_PRE_CROP_PDF if BOOKLET_FINAL_ROTATION is set ---
    if [ -n "$BOOKLET_FINAL_ROTATION" ]; then # Check if rotation variable is not empty
        echo "Rotating booklet PDF by 90 degrees ($BOOKLET_FINAL_ROTATION) for $lang..."
        # Corrected pdftk command: rotation keyword is appended directly to the page range
        if pdftk "$BOOKLET_PRE_CROP_PDF" cat 1-end$BOOKLET_FINAL_ROTATION output "$BOOKLET_TO_CROP_PDF"; then
            echo "Booklet PDF rotated for $lang: $BOOKLET_TO_CROP_PDF"
        else
            echo "Error: pdftk failed to rotate booklet PDF for $lang."
            # Fallback to unrotated if rotation fails
            cp "$BOOKLET_PRE_CROP_PDF" "$BOOKLET_TO_CROP_PDF"
            echo "Using unrotated PDF for crop marks due to rotation error."
        fi
    else
        # If no rotation is specified, just copy the pdfjam output to the next step's input
        cp "$BOOKLET_PRE_CROP_PDF" "$BOOKLET_TO_CROP_PDF"
        echo "No rotation specified for booklet PDF."
    fi

    # --- Add Crop Marks using LaTeX ---
    CROP_LATEX_FILE="$TEMP_DIR/crop_template_${lang}.tex"
    FINAL_BOOKLET_WITH_CROPS="booklet_pipoca_with_crops_${lang}.pdf"

    if [ -f "$BOOKLET_TO_CROP_PDF" ]; then
        echo "Adding crop marks for $lang using LaTeX..."

        # Get dimensions of the imposed PDF (BOOKLET_TO_CROP_PDF) in points
        # This is the actual size of the content that needs to be scaled to A4
        IMPOSED_PDF_WIDTH_PT=$(pdfinfo "$BOOKLET_TO_CROP_PDF" | awk '/Page size:/ {print $3}')
        IMPOSED_PDF_HEIGHT_PT=$(pdfinfo "$BOOKLET_TO_CROP_PDF" | awk '/Page size:/ {print $5}')

        # --- UPDATED: Calculate scaling factor to fit IMPOSED_PDF into EFFECTIVE A4 area (with margins) ---
        LATEX_SCALE_FACTOR_WIDTH=$(awk "BEGIN {print $EFFECTIVE_A4_WIDTH_PT / $IMPOSED_PDF_WIDTH_PT}")
        LATEX_SCALE_FACTOR_HEIGHT=$(awk "BEGIN {print $EFFECTIVE_A4_HEIGHT_PT / $IMPOSED_PDF_HEIGHT_PT}")

        # Use the smaller scale factor to ensure content fits entirely within the effective A4 area
        LATEX_SCALE_FACTOR=$(awk "BEGIN {if ($LATEX_SCALE_FACTOR_WIDTH < $LATEX_SCALE_FACTOR_HEIGHT) print $LATEX_SCALE_FACTOR_WIDTH; else print $LATEX_SCALE_FACTOR_HEIGHT}")

        # Calculate the dimensions of the *scaled* content area for crop marks
        # These are the dimensions of the imposed content *after* it's been scaled to fit the EFFECTIVE A4 area.
        _SCALED_CONTENT_AREA_WIDTH_IN=$(awk "BEGIN {print ($IMPOSED_PDF_WIDTH_PT * $LATEX_SCALE_FACTOR) / 72}")
        _SCALED_CONTENT_AREA_HEIGHT_IN=$(awk "BEGIN {print ($IMPOSED_PDF_HEIGHT_PT * $LATEX_SCALE_FACTOR) / 72}")

        cat <<EOF > "$CROP_LATEX_FILE"
\documentclass[${FINAL_OUTPUT_PAPER_SIZE}paper]{article} % Final output document is A4

\usepackage{pdfpages} % For including PDF
\pagestyle{empty} % Ensure no page numbers
\usepackage[paperheight=${_SCALED_CONTENT_AREA_HEIGHT_IN}in,paperwidth=${_SCALED_CONTENT_AREA_WIDTH_IN}in]{geometry}
\usepackage[axes,cam,${FINAL_OUTPUT_PAPER_SIZE},landscape,pdftex,center]{crop}

\begin{document}
% The \includepdf command places the scaled content.
% The 'crop' package defines the area for crop marks based on _SCALED_CONTENT_AREA_WIDTH_IN/_HEIGHT_IN.
% The combination ensures the content is scaled to fit the effective A4 area,
% and crop marks are drawn around this scaled content, leaving the page margin.
\includepdf[pages=-]{$BOOKLET_TO_CROP_PDF}
\end{document}
EOF
        pdflatex -output-directory="$TEMP_DIR" "$CROP_LATEX_FILE" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            mv "$TEMP_DIR/$(basename "$CROP_LATEX_FILE" .tex).pdf" "$FINAL_BOOKLET_WITH_CROPS"
            echo "Booklet with crop marks for $lang created: $FINAL_BOOKLET_WITH_CROPS"
        else
            echo "Error: pdflatex failed to add crop marks for $lang."
            echo "Please check if 'pdflatex' and required LaTeX packages (crop, pdfpages, geometry) are installed."
            # Uncomment the line below for detailed LaTeX errors if needed:
            # cat "$TEMP_DIR/$(basename "$CROP_LATEX_FILE" .tex).log"
        fi
    else
        echo "Warning: Rotated Booklet PDF ($BOOKLET_TO_CROP_PDF) not found for $lang, skipping crop marks."
    fi

done

echo "Script finished."
