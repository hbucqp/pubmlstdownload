# PubMLST Database Downloader

A high-performance Python tool for downloading MLST (Multilocus Sequence Typing) and cgMLST (core genome MLST) schemes and allele sequences from the [PubMLST](https://pubmlst.org/) and [Pasteur BIGSdb](https://bigsdb.pasteur.fr/) databases using their RESTful APIs.

## Overview

This tool efficiently downloads reference databases from PubMLST and Pasteur BIGSdb, including:
- **Scheme profiles** (ST definitions)
- **Allele sequences** for all loci in FASTA format
- Support for MLST, cgMLST, and other typing schemes
- Covers 60+ bacterial, fungal, and parasite species from PubMLST
- Supports organisms from Pasteur BIGSdb (Listeria, Klebsiella, Bordetella, Corynebacterium, Leptospira, Yersinia, etc.)

## Features

### Performance Optimizations
- **Concurrent downloads**: Uses ThreadPoolExecutor for parallel downloads (10 workers by default)
- **Connection pooling**: Reuses HTTP connections for faster sequential requests
- **Smart retry logic**: Automatically retries failed downloads with exponential backoff (up to 5 attempts)
- **Rate limit handling**: Special handling for 429 (Too Many Requests) errors with progressive delays
- **Resume capability**: Skips already-downloaded files to resume interrupted downloads
- **Progress tracking**: Real-time logging of download progress

### Robustness
- Automatic retry with exponential backoff and jitter
- Handles transient network errors gracefully
- Respects server Retry-After headers
- Saves failed download URLs for manual retry
- Comprehensive error logging with timestamps

## Installation

### Requirements
- Python 3.10 or higher
- Dependencies: `requests`, `urllib3`

### Install from source

```bash
# Clone or download this repository
cd pubmlstdownload

# Install using uv (recommended)
uv pip install -e .

# Or using pip
pip install -e .
```

### Install from pypi

```bash
pip install pubmlstdownload
```

After installation, the `pubmlstdownload` command will be available in your PATH.

## Usage

### Basic Commands

The tool supports three main workflows:

#### 1. Download a specific scheme

```bash
pubmlstdownload \
  -scheme <SCHEME_NAME> \
  -subscheme <SUBSCHEME_NAME> \
  -scheme_url <SCHEME_URL> \
  -output <OUTPUT_DIR>
```

**Example**: Download *Clostridium perfringens* cgMLST scheme
```bash
pubmlstdownload \
  -scheme cperfringens \
  -subscheme cgMLST \
  -scheme_url https://rest.pubmlst.org/db/pubmlst_cperfringens_seqdef/schemes/2 \
  -output ./db
```

#### 2. Update scheme metadata

Fetch or refresh the complete list of available schemes from PubMLST or Pasteur BIGSdb:

```bash
# Update from PubMLST (default)
pubmlstdownload update_schemes

# Update from Pasteur BIGSdb
pubmlstdownload update_schemes -source pasteur

# Force refresh from API (ignore cached data)
pubmlstdownload update_schemes -force_refresh
pubmlstdownload update_schemes -source pasteur -force_refresh
```

This creates/updates `schemes_pubmlst.json` or `schemes_pasteur.json` with all available organisms and typing methods.

#### 3. Show available schemes

Display all available organisms and their typing schemes:

```bash
pubmlstdownload show_schemes
```

Filter by organism:
```bash
pubmlstdownload show_schemes | grep "Vibrio"
```

## Command-Line Options

### Main Arguments

| Argument | Short | Description | Required |
|----------|-------|-------------|----------|
| `--scheme` | `-scheme` | Organism scheme key (e.g., `vcholerae`, `cperfringens`) | Yes* |
| `--subscheme` | `-subscheme` | Typing method (e.g., `MLST`, `cgMLST`) | Yes* |
| `--scheme_url` | `-scheme_url` | Full API URL for the scheme | Yes* |
| `--output` | `-output` | Base output directory (default: `./db`) | Yes* |
| `--source` | `-source` | Data source: `pubmlst` or `pasteur` (default: `pubmlst`) | No |

\* Required only for download mode (no subcommand)

### Performance Tuning

| Argument | Default | Description |
|----------|---------|-------------|
| `--max_workers` | 10 | Maximum concurrent downloads. Reduce to 5 if rate limited. |
| `--max_retries` | 5 | Maximum retry attempts per file (handles 429 errors) |
| `--force_redownload` | False | Redownload files even if they exist |

### Subcommands

| Subcommand | Options | Description |
|------------|---------|-------------|
| `update_schemes` | `-force_refresh`, `-source` | Update/refresh scheme metadata from API (PubMLST or Pasteur BIGSdb) |
| `show_schemes` | `-source` | Display all available schemes from specified source |

## Examples

### Example 1: Download Vibrio cholerae MLST

```bash
pubmlstdownload \
  -scheme vcholerae \
  -subscheme MLST \
  -scheme_url https://rest.pubmlst.org/db/pubmlst_vcholerae_seqdef/schemes/1 \
  -output ./databases
```

**Output structure:**
```
databases/
└── vcholerae/
    └── MLST/
        ├── profile.txt        # ST profiles
        ├── ftsH.fasta         # Locus 1 alleles
        ├── mba-np1.fasta      # Locus 2 alleles
        ├── rpL22.fasta        # Locus 3 alleles
        ├── thrS.fasta
        ├── ureG.fasta
        └── valS.fasta
```

### Example 2: Fast download with more workers

For schemes with many loci, increase workers for faster downloads:

```bash
pubmlstdownload \
  -scheme spneumoniae \
  -subscheme cgMLST \
  -scheme_url https://rest.pubmlst.org/db/pubmlst_spneumoniae_seqdef/schemes/2 \
  -output ./db \
  -max_workers 20
```

### Example 3: Handling rate limits

If you encounter rate limiting (429 errors), reduce concurrent workers:

```bash
pubmlstdownload \
  -scheme neisseria \
  -subscheme cgMLST \
  -scheme_url https://rest.pubmlst.org/db/pubmlst_neisseria_seqdef/schemes/47 \
  -output ./db \
  -max_workers 5 \
  -max_retries 10
```

**Retry behavior for 429 errors:**
- Attempt 1: Retry after ~5 seconds
- Attempt 2: Retry after ~10 seconds
- Attempt 3: Retry after ~20 seconds
- Attempt 4: Retry after ~40 seconds
- Attempt 5: Retry after ~80 seconds

### Example 4: Download from Pasteur BIGSdb

Download Listeria MLST scheme from Pasteur BIGSdb:

```bash
pubmlstdownload \
  -scheme listeria \
  -subscheme MLST \
  -scheme_url https://bigsdb.pasteur.fr/api/db/pubmlst_listeria_seqdef/schemes/1 \
  -output ./db \
  -source pasteur
```

### Example 5: Resume interrupted download

Simply re-run the same command. Files already downloaded will be skipped:

```bash
pubmlstdownload \
  -scheme escherichia \
  -subscheme cgMLST \
  -scheme_url https://rest.pubmlst.org/db/pubmlst_escherichia_seqdef/schemes/6 \
  -output ./db
```

### Example 6: Force redownload all files

```bash
pubmlstdownload \
  -scheme saureus \
  -subscheme MLST \
  -scheme_url https://rest.pubmlst.org/db/pubmlst_saureus_seqdef/schemes/1 \
  -output ./db \
  --force_redownload
```

## Finding Scheme URLs

### Method 1: Use the update_schemes command

```bash
# Update scheme metadata from PubMLST (creates schemes_pubmlst.json)
pubmlstdownload update_schemes -force_refresh

# Update scheme metadata from Pasteur BIGSdb (creates schemes_pasteur.json)
pubmlstdownload update_schemes -source pasteur -force_refresh

# View available schemes from PubMLST
pubmlstdownload show_schemes | grep "Vibrio"

# View available schemes from Pasteur BIGSdb
pubmlstdownload show_schemes -source pasteur | grep "Listeria"
```

This will show output like:

**PubMLST:**
```
Vibrio spp. -> vcholerae -> MLST -> https://rest.pubmlst.org/db/pubmlst_vcholerae_seqdef/schemes/1
Vibrio spp. -> vcholerae -> MLST (O1 and O139) -> https://rest.pubmlst.org/db/pubmlst_vcholerae_seqdef/schemes/2
Vibrio spp. -> vcholerae -> cgMLST -> https://rest.pubmlst.org/db/pubmlst_vcholerae_seqdef/schemes/3
Vibrio spp. -> vparahaemolyticus -> MLST -> https://rest.pubmlst.org/db/pubmlst_vparahaemolyticus_seqdef/schemes/1
```

**Pasteur BIGSdb:**
```
Listeria REST API group -> listeria -> MLST -> https://bigsdb.pasteur.fr/api/db/pubmlst_listeria_seqdef/schemes/1
Listeria REST API group -> listeria -> cgMLST -> https://bigsdb.pasteur.fr/api/db/pubmlst_listeria_seqdef/schemes/2
Klebsiella REST API group -> klebsiella -> MLST -> https://bigsdb.pasteur.fr/api/db/pubmlst_klebsiella_seqdef/schemes/1
Bordetella REST API group -> bordetella -> MLST -> https://bigsdb.pasteur.fr/api/db/pubmlst_bordetella_seqdef/schemes/3
```

### Method 2: Browse API documentation

- **PubMLST API**: Visit https://rest.pubmlst.org/
- **Pasteur BIGSdb API**: Visit https://bigsdb.pasteur.fr/api

### Method 3: Use schemes JSON files

After running `update_schemes`, check the generated JSON files:

```bash
# Using jq to parse JSON (PubMLST)
cat schemes_pubmlst.json | jq '.["Vibrio spp."]'

# Using jq to parse JSON (Pasteur BIGSdb)
cat schemes_pasteur.json | jq '.["Listeria REST API group"]'

# Or use grep
grep -A 2 "vcholerae" schemes_pubmlst.json
grep -A 2 "listeria" schemes_pasteur.json
```

## Common Organisms and Schemes

Here are some frequently used schemes:

### PubMLST Schemes

| Organism | Scheme | URL |
|----------|--------|-----|
| *Vibrio cholerae* | MLST | `https://rest.pubmlst.org/db/pubmlst_vcholerae_seqdef/schemes/1` |
| *Vibrio parahaemolyticus* | MLST | `https://rest.pubmlst.org/db/pubmlst_vparahaemolyticus_seqdef/schemes/1` |
| *Escherichia coli* | MLST (Achtman) | `https://rest.pubmlst.org/db/pubmlst_escherichia_seqdef/schemes/1` |
| *Escherichia coli* | cgMLST | `https://rest.pubmlst.org/db/pubmlst_escherichia_seqdef/schemes/6` |
| *Staphylococcus aureus* | MLST | `https://rest.pubmlst.org/db/pubmlst_saureus_seqdef/schemes/1` |
| *Neisseria meningitidis* | MLST | `https://rest.pubmlst.org/db/pubmlst_neisseria_seqdef/schemes/1` |
| *Salmonella* | MLST | `https://rest.pubmlst.org/db/pubmlst_salmonella_seqdef/schemes/2` |
| *Campylobacter jejuni* | MLST | `https://rest.pubmlst.org/db/pubmlst_campylobacter_seqdef/schemes/1` |

### Pasteur BIGSdb Schemes

| Organism | Scheme | URL |
|----------|--------|-----|
| *Listeria* | MLST | `https://bigsdb.pasteur.fr/api/db/pubmlst_listeria_seqdef/schemes/1` |
| *Klebsiella* | MLST | `https://bigsdb.pasteur.fr/api/db/pubmlst_klebsiella_seqdef/schemes/1` |
| *Bordetella* | MLST | `https://bigsdb.pasteur.fr/api/db/pubmlst_bordetella_seqdef/schemes/3` |
| *Bordetella* | cgMLST | `https://bigsdb.pasteur.fr/api/db/pubmlst_bordetella_seqdef/schemes/1` |
| *Corynebacterium* | MLST | `https://bigsdb.pasteur.fr/api/db/pubmlst_diphtheria_seqdef/schemes/1` |
| *Yersinia* | MLST | `https://bigsdb.pasteur.fr/api/db/pubmlst_yersinia_seqdef/schemes/1` |

Run `pubmlstdownload show_schemes` (for PubMLST) or `pubmlstdownload show_schemes -source pasteur` (for Pasteur BIGSdb) for the complete list.

## Output Structure

Downloaded files are organized hierarchically:

```
<output_dir>/
└── <scheme>/
    └── <subscheme>/
        ├── profile.txt              # ST allelic profiles (tab-delimited)
        ├── <locus1>.fasta          # Allele sequences for locus 1
        ├── <locus2>.fasta          # Allele sequences for locus 2
        └── ...
        └── failed_downloads.txt     # URLs that failed (only if errors occurred)
```

**Example for V. cholerae MLST:**
```
db/
└── vcholerae/
    └── MLST/
        ├── profile.txt       # 7-locus ST definitions
        ├── ftsH.fasta        # ~500 alleles
        ├── mba-np1.fasta     # ~400 alleles
        ├── rpL22.fasta
        ├── thrS.fasta
        ├── ureG.fasta
        └── valS.fasta
```

## Troubleshooting

### Problem: Rate limiting (429 errors)

**Symptoms:**
```
ERROR - Failed to fetch locus metadata: Max retries exceeded (429 error responses)
```

**Solution**: Reduce concurrent workers and increase retry attempts
```bash
pubmlstdownload ... -max_workers 5 -max_retries 10
```

### Problem: Connection timeouts

**Symptoms:**
```
WARNING - Failed to fetch locus metadata: Connection timeout
```

**Solution**: Increase retry attempts
```bash
pubmlstdownload ... -max_retries 10
```

### Problem: Download interrupted

**Solution**: Just re-run the same command. Already-downloaded files will be skipped automatically.
```bash
# Run again with the same parameters
pubmlstdownload -scheme vcholerae -subscheme MLST -scheme_url <URL> -output ./db
```

### Problem: Need to redownload everything

**Solution**: Use the `--force_redownload` flag
```bash
pubmlstdownload ... --force_redownload
```

### Failed Downloads

If some files fail after all retries, check `failed_downloads.txt` in the output directory:

```bash
cat db/vcholerae/MLST/failed_downloads.txt
```

You can manually investigate these URLs or retry with increased settings.

## Performance Tips

1. **Start with default settings** (10 workers, 5 retries) - works for most cases
2. **If rate limited**: Reduce to `-max_workers 5` or even `-max_workers 3`
3. **For large schemes** (1000+ loci like cgMLST): 
   - Be patient, downloads may take 10-30 minutes depending on scheme size
   - Concurrent downloads are still 5-10× faster than sequential
4. **Monitor logs**: Watch for patterns in failures to adjust settings
5. **Use resume**: If interrupted, just re-run - it will skip completed files

## Logging

The tool provides detailed timestamped logging:

| Level | Description |
|-------|-------------|
| **INFO** | Progress updates, successful operations |
| **WARNING** | Retries, rate limit warnings |
| **ERROR** | Critical failures |

Example log output:
```
2025-10-16 09:30:07 - INFO - Starting download for cperfringens/cgMLST...
2025-10-16 09:30:08 - INFO - Found 2208 loci to download
2025-10-16 09:30:08 - INFO - Starting concurrent download of 2208 loci (max_workers=10, max_retries=5)...
2025-10-16 09:30:15 - INFO - Progress: 10/2208 loci processed
2025-10-16 09:30:18 - WARNING - Rate limited at <URL>, retry 1/5 after 5.2s
2025-10-16 09:30:45 - INFO - Progress: 50/2208 loci processed
...
2025-10-16 09:45:12 - INFO - Successfully downloaded all 2208 loci
2025-10-16 09:45:12 - INFO - Completed download for cperfringens/cgMLST
```

## Advanced Usage

### Programmatic Use

```python
from pathlib import Path
from pubmlstdownload.pubmlst_download import download_ref_db, build_or_load_schemes

# Download a scheme programmatically
download_ref_db(
    scheme='vcholerae',
    subscheme='MLST',
    scheme_url='https://rest.pubmlst.org/db/pubmlst_vcholerae_seqdef/schemes/1',
    output_path=Path('./db'),
    max_workers=10,
    skip_existing=True,
    max_retries=5
)

# Load scheme metadata
schemes = build_or_load_schemes(Path('schemes.json'), force_refresh=False)

# Access scheme information
for organism, databases in schemes.items():
    for db_name, methods in databases.items():
        for method in methods:
            print(f"{organism} - {method['method']}: {method['typing_method_url']}")
```

### Batch Downloads

Create a shell script for multiple schemes:

```bash
#!/bin/bash

# Define schemes to download (space-separated: scheme subscheme url)
schemes=(
  "vcholerae MLST https://rest.pubmlst.org/db/pubmlst_vcholerae_seqdef/schemes/1"
  "saureus MLST https://rest.pubmlst.org/db/pubmlst_saureus_seqdef/schemes/1"
  "ecoli MLST https://rest.pubmlst.org/db/pubmlst_escherichia_seqdef/schemes/1"
)

for entry in "${schemes[@]}"; do
  read scheme subscheme url <<< "$entry"
  echo "Downloading $scheme $subscheme..."
  pubmlstdownload \
    -scheme "$scheme" \
    -subscheme "$subscheme" \
    -scheme_url "$url" \
    -output ./db \
    -max_workers 10
done

echo "All downloads complete!"
```

### Using with Python Scripts

```python
#!/usr/bin/env python3
import subprocess
from pathlib import Path

schemes_to_download = [
    {
        'scheme': 'vcholerae',
        'subscheme': 'MLST',
        'url': 'https://rest.pubmlst.org/db/pubmlst_vcholerae_seqdef/schemes/1'
    },
    {
        'scheme': 'vparahaemolyticus',
        'subscheme': 'MLST',
        'url': 'https://rest.pubmlst.org/db/pubmlst_vparahaemolyticus_seqdef/schemes/1'
    }
]

for s in schemes_to_download:
    cmd = [
        'pubmlstdownload',
        '-scheme', s['scheme'],
        '-subscheme', s['subscheme'],
        '-scheme_url', s['url'],
        '-output', './db'
    ]
    subprocess.run(cmd, check=True)
```

## Project Structure

```
pubmlst_download/
├── README.md                           # This file
├── pyproject.toml                      # Package configuration
├── src/
│   └── pubmlstdownload/
│       ├── __init__.py                 # Package initialization
│       ├── pubmlst_download.pyx        # Main module (Cython-compiled)
│       ├── schemes_pubmlst.json        # Cached PubMLST scheme metadata
│       └── schemes_pasteur.json        # Cached Pasteur BIGSdb scheme metadata
├── db/                                 # Downloaded databases (default output)
│   └── <scheme>/
│       └── <subscheme>/
│           ├── profile.txt
│           └── *.fasta
└── dist/                               # Built packages (wheels)
```

## Development

### Building from source

```bash
# Using uv (recommended)
uv build

# Or using pip with build
pip install build
python -m build

# Install in editable mode for development
uv pip install -e .
```

### Running tests

```bash
# Test basic functionality (PubMLST)
pubmlstdownload update_schemes

# Test basic functionality (Pasteur BIGSdb)
pubmlstdownload update_schemes -source pasteur

# Test download with a small scheme (PubMLST)
pubmlstdownload \
  -scheme achromobacter \
  -subscheme MLST \
  -scheme_url https://rest.pubmlst.org/db/pubmlst_achromobacter_seqdef/schemes/1 \
  -output ./test_db

# Test download with a small scheme (Pasteur BIGSdb)
pubmlstdownload \
  -scheme listeria \
  -subscheme MLST \
  -scheme_url https://bigsdb.pasteur.fr/api/db/pubmlst_listeria_seqdef/schemes/1 \
  -output ./test_db \
  -source pasteur
```

## FAQ

### Q: How long does a download take?

**A:** Depends on the scheme size:
- **MLST** (7-10 loci): 10-30 seconds
- **cgMLST** (1000-3000 loci): 10-30 minutes
- Progress is logged every 10 files

### Q: Can I download multiple schemes at once?

**A:** Not directly, but you can:
1. Use a bash script (see Batch Downloads example)
2. Run multiple instances with different output directories
3. Call the Python API in a loop

### Q: What if a download fails partway through?

**A:** Just re-run the same command. The tool automatically:
- Skips files that were already downloaded
- Retries only failed/missing files
- Saves failed URLs to `failed_downloads.txt`

### Q: How do I know what schemes are available?

**A:** Several ways:
1. Run `pubmlstdownload show_schemes` (for PubMLST) or `pubmlstdownload show_schemes -source pasteur` (for Pasteur BIGSdb)
2. Check `schemes_pubmlst.json` or `schemes_pasteur.json` after running `update_schemes`
3. Browse https://pubmlst.org/ (for PubMLST) or https://bigsdb.pasteur.fr/api (for Pasteur BIGSdb)

### Q: Why do I get 429 errors?

**A:** Both PubMLST and Pasteur BIGSdb have rate limits. Solutions:
- Reduce `-max_workers` to 5 or 3
- Increase `-max_retries` to 10
- The tool automatically backs off with progressive delays

### Q: What's the difference between PubMLST and Pasteur BIGSdb?

**A:** Both are BIGSdb-based systems hosting MLST/cgMLST schemes:
- **PubMLST** (https://pubmlst.org/): The primary PubMLST database hosted at the University of Oxford
- **Pasteur BIGSdb** (https://bigsdb.pasteur.fr/): Pasteur Institute's BIGSdb instance hosting additional organisms like Listeria, Klebsiella, Bordetella, Corynebacterium, Leptospira, and Yersinia

Use the `-source` parameter to switch between them.

### Q: Can I use this in my own Python package?

**A:** Yes! Install it as a dependency:
```toml
# pyproject.toml
dependencies = [
    "pubmlstdownload>=0.1.0"
]
```

Then import and use:
```python
from pubmlstdownload.pubmlst_download import download_ref_db
```



## Citation

If you use PubMLST data in your research, please cite:

> Jolley KA, Bray JE, Maiden MCJ. Open-access bacterial population genomics: BIGSdb software, the PubMLST.org website and their applications. *Wellcome Open Res* 2018, 3:124  
> https://doi.org/10.12688/wellcomeopenres.14826.1

## License

This tool is provided for research and educational purposes.

PubMLST data is subject to its own terms of use. Please review at https://pubmlst.org/

## Author

**Qingpo Cui**  
SZQ Lab, China Agricultural University

## Contributing

Contributions are welcome! Please:
1. Test your changes thoroughly
2. Follow existing code style
3. Add docstrings for new functions
4. Update README for new features

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Review log output for specific error messages
3. Try reducing `-max_workers` if experiencing rate limits

## Changelog

### Version 0.3.0 (2025-12-12)
- Added support for Pasteur BIGSdb database as a data source
- Fixed Pasteur BIGSdb scheme parsing to detect both "seqdef" and "definitions" database types
- Improved compatibility with Pasteur BIGSdb API structure
- Fixed `Optional` type hint import issue
- Added `-source` parameter to specify data source ('pubmlst' or 'pasteur')
- Enhanced `get_pasteur_schemes()` function to properly handle all organisms including Listeria

### Version 0.1.0 (2025-10-16)
- Initial release
- Concurrent downloads with ThreadPoolExecutor (10 workers default)
- Automatic retry logic with exponential backoff (5 attempts)
- Enhanced rate limit (429) handling with progressive delays
- Connection pooling and session reuse
- Resume capability (skip existing files)
- Failed download tracking (`failed_downloads.txt`)
- Comprehensive logging with timestamps
- Scheme metadata caching (`schemes.json`)
- CLI with update_schemes and show_schemes subcommands
- Support for MLST, cgMLST, and custom typing schemes
- Pathlib-based file operations
- Cython compilation for improved performance
