"""
PubMLST and Pasteur BIGSdb Database Downloader

Downloads MLST/cgMLST schemes and alleles from PubMLST or Pasteur BIGSdb using their RESTful APIs.

Performance optimizations:
- Concurrent downloads using ThreadPoolExecutor (10 workers by default)
- Connection pooling and reuse via requests.Session
- Automatic retry logic for transient failures
- Skip existing files to resume interrupted downloads
- Progress tracking and detailed logging

Author: Qingpo Cui (SZQ Lab, China Agricultural University)
"""

import argparse
import sys
import re
import json
import logging
import time
import random
import requests
from typing import List, Dict, Any, Tuple, Callable, Optional
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry




# Configure logging system for the entire application
# This sets up a centralized logging system that will be used throughout the pipeline
logging.basicConfig(
    level=logging.INFO,  # Set minimum log level to INFO (INFO, WARNING, ERROR, CRITICAL will be shown)
    format='%(asctime)s - %(levelname)s - %(message)s',  # Format: timestamp - level - message
    datefmt='%Y-%m-%d %H:%M:%S'  # Date format: YYYY-MM-DD HH:MM:SS
)
# Create a logger instance for this module
# This allows us to use logger.info(), logger.error(), etc. throughout the code
logger = logging.getLogger(__name__)

# Global settings for concurrent downloads
MAX_WORKERS = 10  # Maximum number of concurrent downloads
MAX_RETRIES = 5  # Maximum number of retries for individual downloads
INITIAL_DELAY = 0.1  # Small delay between concurrent requests to avoid overwhelming server
RETRY_STRATEGY = Retry(
    total=5,  # Increased from 3 to handle more transient failures
    backoff_factor=2,  # Exponential backoff: 2, 4, 8, 16, 32 seconds
    status_forcelist=[429, 500, 502, 503, 504],
    respect_retry_after_header=True,  # Honor Retry-After header from server
)

# Pasteur BIGSdb API settings
PASTEUR_BASE_URL = 'https://bigsdb.pasteur.fr/api'


def get_session() -> requests.Session:
    """
    Create a requests session with connection pooling and retry strategy.
    This improves performance by reusing connections and handling transient failures.
    """
    session = requests.Session()
    adapter = HTTPAdapter(
        max_retries=RETRY_STRATEGY,
        pool_connections=20,
        pool_maxsize=20
    )
    session.mount('http://', adapter)
    session.mount('https://', adapter)
    
    return session


def retry_with_backoff(func: Callable, *args, max_retries: int = MAX_RETRIES, 
                       initial_delay: float = 1.0, **kwargs) -> Any:
    """
    Retry a function with exponential backoff and jitter.
    Useful for handling rate limiting (429) and transient network errors.
    
    Args:
        func: Function to retry
        *args: Positional arguments for func
        max_retries: Maximum number of retry attempts
        initial_delay: Initial delay in seconds (doubles each retry)
        **kwargs: Keyword arguments for func
    
    Returns:
        Result from func on success
        
    Raises:
        Last exception if all retries fail
    """
    last_exception = None
    
    for attempt in range(max_retries):
        try:
            return func(*args, **kwargs)
        except (requests.exceptions.RequestException, 
                requests.exceptions.ConnectionError,
                requests.exceptions.Timeout) as e:
            last_exception = e
            if attempt < max_retries - 1:
                # Calculate delay with exponential backoff and jitter
                delay = initial_delay * (2 ** attempt) + random.uniform(0, 1)
                logger.warning(f'Attempt {attempt + 1}/{max_retries} failed: {e}. Retrying in {delay:.1f}s...')
                time.sleep(delay)
            else:
                logger.error(f'All {max_retries} attempts failed for {func.__name__}')
                raise last_exception
    
    raise last_exception if last_exception else Exception('Retry failed')


def fetch_resources(base_url: str = 'https://rest.pubmlst.org') -> List[Dict[str, Any]]:
    """
    Fetch top-level resources from PubMLST or Pasteur BIGSdb API with a timeout and simple error handling.
    Uses a session for better connection reuse.
    
    Args:
        base_url: Base URL for the API
        auth_token: Optional OAuth2 bearer token for Pasteur BIGSdb
    """
    session = get_session()
    try:
        response = session.get(base_url, timeout=15)
        response.raise_for_status()
        return response.json()
    except Exception as e:
        logger.error(f'Failed to fetch base resources from {base_url}: {e}')
        return []


def get_pubmlst_schemes(resources: List[Dict[str, Any]]) -> Dict[str, Dict[str, List[Dict[str, str]]]]:
    """
    Function to list organisms and scheme definitions using the PubMLST RESTful API.
    Uses a shared session for better performance across multiple requests.
    
    Args:
        resources: List of resource dictionaries from the API
    """
    session = get_session()
    info_dict = {}
    
    for resource in resources:
        if resource.get('databases'):
            organism_name = resource['description']
            if not re.search('Example', organism_name):
                logger.info(f'Parsing {organism_name} ...')
                schemes_dict = {}
                
                for db in resource['databases']:
                    if re.search('definitions', db['description']):
                        subscheme = db['name']
                        try:
                            db_attributes = session.get(db['href'], timeout=15).json()
                        except Exception as e:
                            logger.warning(f'Failed to fetch db attributes for {subscheme}: {e}')
                            continue
                        
                        if 'schemes' in db_attributes:
                            try:
                                scheme_list_dict = session.get(db_attributes['schemes'], timeout=15).json()
                            except Exception as e:
                                logger.warning(f'Failed to fetch schemes list for {subscheme}: {e}')
                                continue
                            
                            schemes = scheme_list_dict.get('schemes', [])
                            info_list = []
                            
                            for item in schemes:
                                info_list.append({
                                    'method': item['description'],
                                    'typing_method_url': item['scheme']
                                })
                            schemes_dict[subscheme] = info_list
                
                info_dict[organism_name] = schemes_dict
    
    return info_dict


def get_pasteur_schemes(resources: List[Dict[str, Any]]) -> Dict[str, Dict[str, List[Dict[str, str]]]]:
    """
    Function to list organisms and scheme definitions using the Pasteur BIGSdb RESTful API.
    Uses a shared session for better performance across multiple requests.
    
    Args:
        resources: List of resource dictionaries from the API
    """
    session = get_session()
    info_dict = {}
    
    # Pasteur BIGSdb API structure may differ, adapt as needed
    for resource in resources:
        if resource.get('databases'):
            organism_name = resource.get('description', resource.get('name', 'Unknown'))
            if not re.search('Example', organism_name, re.IGNORECASE):
                logger.info(f'Parsing {organism_name} ...')
                schemes_dict = {}
                
                for db in resource['databases']:
                    if re.search('definitions', db.get('description', ''), re.IGNORECASE):
                        subscheme = db.get('name', '')
                        try:
                            db_attributes = session.get(db['href'], timeout=15).json()
                        except Exception as e:
                            logger.warning(f'Failed to fetch db attributes for {subscheme}: {e}')
                            continue
                        
                        if 'schemes' in db_attributes:
                            try:
                                scheme_list_dict = session.get(db_attributes['schemes'], timeout=15).json()
                            except Exception as e:
                                logger.warning(f'Failed to fetch schemes list for {subscheme}: {e}')
                                continue
                            
                            schemes = scheme_list_dict.get('schemes', [])
                            info_list = []
                            
                            for item in schemes:
                                info_list.append({
                                    'method': item.get('description', ''),
                                    'typing_method_url': item.get('scheme', '')
                                })
                            schemes_dict[subscheme] = info_list
                
                if schemes_dict:
                    info_dict[organism_name] = schemes_dict
    
    return info_dict

def load_schemes(file_path: Path) -> Dict[str, Any]:
    """
    Load schemes mapping from a JSON file. Returns empty dict if missing or invalid.
    """
    if not file_path.exists():
        return {}
    try:
        with open(file_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.warning(f'Failed to load {file_path}: {e}')
        return {}


def save_schemes(file_path: Path, data: Dict[str, Any]) -> None:
    """
    Save schemes mapping to a JSON file with pretty formatting.
    """
    try:
        with open(file_path, 'w') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        logger.error(f'Failed to write {file_path}: {e}')


def build_or_load_schemes(schemes_path: Path, force_refresh: bool = False, 
                         source: str = 'pubmlst') -> Dict[str, Any]:
    """
    Build schemes from API or load from disk, controlled by force_refresh flag.
    
    Args:
        schemes_path: Path to schemes JSON file
        force_refresh: If True, force refresh from API
        source: Data source ('pubmlst' or 'pasteur')
    """
    if not force_refresh:
        cached = load_schemes(schemes_path)
        if cached:
            return cached
    
    if source == 'pasteur':
        base_url = PASTEUR_BASE_URL
        resources = fetch_resources(base_url)
        data = get_pasteur_schemes(resources)
    else:  # default to pubmlst
        base_url = 'https://rest.pubmlst.org'
        resources = fetch_resources(base_url)
        data = get_pubmlst_schemes(resources)
    
    save_schemes(schemes_path, data)
    return data


def output_scheme_info(info_dict):
    """
    Obtain schemes of specific organism
    """
    print('Organism -> Species -> Method -> Method_url')
    for organism in info_dict.keys():
        scheme_dict = info_dict[organism]
        for item in scheme_dict.keys():
            species = item.replace('pubmlst_', '').replace('_seqdef', '')
            for value in scheme_dict[item]:
                method = value['method']
                method_url = value['typing_method_url']
                print(f'{organism} -> {species} -> {method} -> {method_url}')


def download_ref_db(scheme: str, subscheme: str, scheme_url: str, output_path: Path, 
                    max_workers: int = MAX_WORKERS, skip_existing: bool = True, 
                    max_retries: int = MAX_RETRIES) -> None:
    """
    Download a complete reference database scheme including profiles and all loci.
    
    The scheme_url should return JSON with structure:
    {
        'locus_count': 7,
        'profiles_csv': 'https://...',
        'loci': ['https://...', ...],
        ...
    }
    
    Args:
        scheme: Organism scheme key (e.g., 'vcholerae')
        subscheme: Typing method (e.g., 'MLST', 'cgMLST')
        scheme_url: API URL for the scheme metadata
        output_path: Base directory for downloads
        max_workers: Maximum concurrent downloads for loci
        skip_existing: Skip files that already exist (default: True)
        max_retries: Maximum retry attempts per locus (default: MAX_RETRIES)
    """
    download_path = Path(output_path) / scheme / subscheme
    if not download_path.exists():
        download_path.mkdir(parents=True, exist_ok=True)
    
    logger.info(f'Starting download for {scheme}/{subscheme}...')
    session = get_session()
    
    try:
        response = session.get(scheme_url, timeout=30).json()
    except Exception as e:
        logger.error(f'Failed to fetch scheme metadata from {scheme_url}: {e}')
        return
    
    locus_url_list = response.get('loci', [])
    if not locus_url_list:
        logger.warning(f'No loci found in scheme {scheme}/{subscheme}')
        return
    
    logger.info(f'Found {len(locus_url_list)} loci to download')
    
    # Download profiles first (usually quick)
    if 'profiles_csv' in response:
        download_profiles(response['profiles_csv'], download_path, session, skip_existing=skip_existing)
    
    # Download all loci concurrently
    download_alleles_seq(locus_url_list, download_path, max_workers=max_workers, 
                        skip_existing=skip_existing, max_retries=max_retries)
    logger.info(f'Completed download for {scheme}/{subscheme}')



def download_alleles_seq(scheme_url: List[str], storage_dir: Path, max_workers: int = MAX_WORKERS, 
                         skip_existing: bool = True, max_retries: int = MAX_RETRIES) -> None:
    """
    Download loci alleles sequences concurrently for improved performance.
    Uses ThreadPoolExecutor to download multiple loci in parallel.
    
    Args:
        scheme_url: List of locus URLs
        storage_dir: Directory to save files
        max_workers: Number of concurrent download threads
        skip_existing: Skip files that already exist
        max_retries: Maximum retry attempts per locus
    """
    storage_dir = Path(storage_dir)
    total = len(scheme_url)
    logger.info(f'Starting concurrent download of {total} loci (max_workers={max_workers}, max_retries={max_retries})...')
    
    session = get_session()
    failed_downloads = []
    skipped = 0
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit all download tasks with small stagger to avoid overwhelming server
        future_to_url = {}
        for i, loci_url in enumerate(scheme_url):
            future = executor.submit(download_loci_seq, loci_url, storage_dir, session, skip_existing, max_retries)
            future_to_url[future] = loci_url
            # Small stagger for first batch to avoid thundering herd
            if i < max_workers:
                time.sleep(INITIAL_DELAY)
        
        # Process completed downloads
        completed = 0
        for future in as_completed(future_to_url):
            loci_url = future_to_url[future]
            try:
                success = future.result()
                completed += 1
                if not success:
                    failed_downloads.append(loci_url)
                if completed % 10 == 0 or completed == total:
                    logger.info(f'Progress: {completed}/{total} loci processed')
            except Exception as e:
                logger.error(f'Unexpected error downloading {loci_url}: {e}')
                failed_downloads.append(loci_url)
                completed += 1
    
    if failed_downloads:
        logger.warning(f'Failed to download {len(failed_downloads)}/{total} loci')
        # Save failed URLs for manual retry
        failed_file = storage_dir / 'failed_downloads.txt'
        try:
            with open(failed_file, 'w') as f:
                for url in failed_downloads:
                    f.write(f'{url}\n')
            logger.info(f'Failed URLs saved to {failed_file} for manual retry')
        except Exception as e:
            logger.error(f'Could not save failed URLs: {e}')
    else:
        logger.info(f'Successfully downloaded all {total} loci')


def download_loci_seq(loci_url: str, storage_dir: Path, session: Optional[requests.Session] = None, 
                      skip_existing: bool = True, max_retries: int = MAX_RETRIES) -> bool:
    """
    Download a single locus FASTA file with retry logic. Returns True on success, False on failure.
    
    Args:
        loci_url: URL to the locus metadata
        storage_dir: Directory to save the FASTA file
        session: Optional session for connection reuse
        skip_existing: If True, skip download if file already exists (default: True)
        max_retries: Maximum retry attempts for this locus (default: MAX_RETRIES)
    """
    if session is None:
        session = get_session()
    
    # Fetch locus metadata with retry
    locus_att = None
    for attempt in range(max_retries):
        try:
            response = session.get(loci_url, timeout=30)
            response.raise_for_status()
            locus_att = response.json()
            break
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 429:
                # Rate limited - use longer backoff
                delay = 5 * (2 ** attempt) + random.uniform(0, 2)
                if attempt < max_retries - 1:
                    logger.warning(f'Rate limited at {loci_url}, retry {attempt + 1}/{max_retries} after {delay:.1f}s')
                    time.sleep(delay)
                else:
                    logger.error(f'Rate limit exceeded for {loci_url} after {max_retries} attempts')
                    return False
            else:
                logger.error(f'HTTP error fetching {loci_url}: {e}')
                return False
        except Exception as e:
            delay = 2 * (2 ** attempt) + random.uniform(0, 1)
            if attempt < max_retries - 1:
                logger.warning(f'Failed to fetch locus metadata at {loci_url}: {e}. Retry {attempt + 1}/{max_retries} after {delay:.1f}s')
                time.sleep(delay)
            else:
                logger.error(f'Failed to fetch locus metadata at {loci_url} after {max_retries} attempts: {e}')
                return False
    
    if not locus_att:
        logger.error(f'No locus metadata retrieved from {loci_url}')
        return False
    
    loci_name = locus_att.get('id')
    if not loci_name:
        logger.error(f'No locus ID found in response from {loci_url}')
        return False
    
    storage_dir = Path(storage_dir)
    outfile = storage_dir / f'{loci_name}.fasta'
    
    # Skip if file already exists and skip_existing is enabled
    if skip_existing and outfile.exists() and outfile.stat().st_size > 0:
        logger.debug(f'Skipping {loci_name}.fasta (already exists)')
        return True
    
    fasta_url = locus_att.get('alleles_fasta')
    if not fasta_url:
        logger.error(f'No alleles_fasta URL for locus {loci_name}')
        return False
    
    # Download FASTA with retry
    for attempt in range(max_retries):
        try:
            seqs = session.get(fasta_url, timeout=60)
            seqs.raise_for_status()
            with open(outfile, 'w') as out_fasta:
                out_fasta.write(seqs.text)
            logger.debug(f'Downloaded {loci_name}.fasta')
            return True
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 429:
                delay = 5 * (2 ** attempt) + random.uniform(0, 2)
                if attempt < max_retries - 1:
                    logger.warning(f'Rate limited downloading {loci_name}, retry {attempt + 1}/{max_retries} after {delay:.1f}s')
                    time.sleep(delay)
                else:
                    logger.error(f'Rate limit exceeded for {loci_name} after {max_retries} attempts')
                    return False
            else:
                logger.error(f'HTTP error downloading {loci_name}: {e}')
                return False
        except Exception as e:
            delay = 2 * (2 ** attempt) + random.uniform(0, 1)
            if attempt < max_retries - 1:
                logger.warning(f'Failed to download {loci_name}: {e}. Retry {attempt + 1}/{max_retries} after {delay:.1f}s')
                time.sleep(delay)
            else:
                logger.error(f'Failed to download {loci_name} after {max_retries} attempts: {e}')
                return False
    
    return False


def download_profiles(profiles_url: str, storage_dir: Path, session: Optional[requests.Session] = None,
                      skip_existing: bool = True) -> bool:
    """
    Download profiles CSV file. Returns True on success, False on failure.
    
    Args:
        profiles_url: URL to the profiles CSV
        storage_dir: Directory to save the file
        session: Optional session for connection reuse
        skip_existing: If True, skip download if file already exists
    """
    if session is None:
        session = get_session()
    
    storage_dir = Path(storage_dir)
    profiles_out = storage_dir / 'profile.txt'
    
    # Skip if file already exists
    if skip_existing and profiles_out.exists() and profiles_out.stat().st_size > 0:
        logger.debug(f'Skipping profile.txt (already exists)')
        return True
    
    try:
        profiles = session.get(profiles_url, timeout=60)
        profiles.raise_for_status()
    except Exception as e:
        logger.error(f'Failed to download profiles from {profiles_url}: {e}')
        return False
    
    try:
        with open(profiles_out, 'w') as output:
            output.write(profiles.text)
        logger.info(f'Downloaded profiles to {profiles_out}')
        return True
    except Exception as e:
        logger.error(f'Failed to write profiles to {profiles_out}: {e}')
        return False



def arg_parse():
    "Parse the input argument, use '-h' for help."
    parser = argparse.ArgumentParser(description='Download MLST/cgMLST schemes from PubMLST or Pasteur BIGSdb using RESTful API',
                                     usage='pubmlst_download -scheme SCHEME_NAME -subscheme SUBSCHEME_NAME -scheme_url SCHEME_URL\n\nAuthor: Qingpo Cui(SZQ Lab, China Agricultural University)\n')
    
    # Add subcommand
    subparsers = parser.add_subparsers(
        dest='subcommand', title='pubmlst_download subcommand')

    # Create database subcommand
    update_schemes_parser = subparsers.add_parser(
        'update_schemes', help='Update schemes')
    update_schemes_parser.add_argument(
        '-force_refresh', action='store_true', help='Force refresh schemes')
    update_schemes_parser.add_argument(
        '-source', choices=['pubmlst', 'pasteur'], default='pubmlst',
        help='Data source: pubmlst or pasteur (default: pubmlst)')

    show_schemes_parser = subparsers.add_parser(
        'show_schemes', help='Show schemes')
    show_schemes_parser.add_argument(
        '-source', choices=['pubmlst', 'pasteur'], default='pubmlst',
        help='Data source: pubmlst or pasteur (default: pubmlst)')
    
   
    # Main command arguments
    parser.add_argument('-scheme', '--scheme',
                      help='Organism scheme key (e.g., vcholerae)')
    parser.add_argument('-subscheme', '--subscheme',
                      help='wgMLST/cgMLST database name')
    parser.add_argument('-scheme_url', '--scheme_url',
                      help='Scheme URL from PubMLST or Pasteur BIGSdb API')
    parser.add_argument('-output', '--output',
                      help='Base output directory (defaults to ./db)')
    parser.add_argument('-source', choices=['pubmlst', 'pasteur'], default='pubmlst',
                      help='Data source: pubmlst or pasteur (default: pubmlst)')
    parser.add_argument('-max_workers', '--max_workers', type=int, default=MAX_WORKERS,
                      help=f'Maximum concurrent downloads (default: {MAX_WORKERS}). Reduce if rate limited.')
    parser.add_argument('-max_retries', '--max_retries', type=int, default=MAX_RETRIES,
                      help=f'Maximum retry attempts per locus (default: {MAX_RETRIES})')
    parser.add_argument('-force_redownload', action='store_true',
                      help='Force redownload even if files already exist')
    
    # If no arguments provided, print help and exit
    if len(sys.argv) == 1:
        parser.print_help(sys.stderr)
        sys.exit(1)

    args = parser.parse_args()
    
    # If subcommand is create_db but no additional arguments, print its help
    if args.subcommand == 'update_schemes' and len(sys.argv) == 2:
        update_schemes_parser.print_help(sys.stderr)
        sys.exit(1)

    # if args.subcommand == 'show_schemes' and len(sys.argv) == 2:
    #     show_schemes_parser.print_help(sys.stderr)
    #     sys.exit(1)
    
    # Validate arguments based on subcommand
    if args.subcommand is None:
        # If no subcommand, require main command arguments
        if not all([args.scheme, args.subscheme, args.scheme_url, args.output]):
            parser.error("the following arguments are required: -scheme/--scheme, -subscheme/--subscheme, -scheme_url/--scheme_url, -output/--output")
    
    return args




def main():
    # get the path of the current script
    current_path = Path(__file__).parent
    args = arg_parse()
    source = getattr(args, 'source', 'pubmlst')
    schemes_path = current_path / f'schemes_{source}.json'
    
    if args.subcommand is None:
        if not schemes_path.exists():
            schemes_path.touch()
        info_dict = build_or_load_schemes(schemes_path, force_refresh=getattr(args, 'force_refresh', False),
                                         source=args.source)
        # show the scheme info
        # output_scheme_info(info_dict)
        base_output = Path(args.output)
        if not base_output.exists():
            base_output.mkdir(parents=True, exist_ok=True)
        max_workers = getattr(args, 'max_workers', MAX_WORKERS)
        max_retries = getattr(args, 'max_retries', MAX_RETRIES)
        skip_existing = not getattr(args, 'force_redownload', False)
        download_ref_db(args.scheme, args.subscheme, args.scheme_url, base_output, 
                       max_workers=max_workers, skip_existing=skip_existing, 
                       max_retries=max_retries)
    elif args.subcommand == 'update_schemes':
        # if the schemes.json is not exists, create it
        if not schemes_path.exists():
            schemes_path.touch()
        info_dict = build_or_load_schemes(schemes_path, force_refresh=getattr(args, 'force_refresh', False),
                                         source=args.source)
        # show the scheme info
        output_scheme_info(info_dict)
    elif args.subcommand == 'show_schemes':
        # show the scheme info
        if not schemes_path.exists():
            schemes_path.touch()
        info_dict = build_or_load_schemes(schemes_path, force_refresh=getattr(args, 'force_refresh', False),
                                         source=args.source)
        output_scheme_info(info_dict)
    else:
        logger.info(f'{args.subcommand} do not exists, please using "pubmlst_download -h" to show help massage.')
    
if __name__ == '__main__':
    main()

