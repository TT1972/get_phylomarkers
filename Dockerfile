## Dockerfile version 2025-03-21, associated with GitHub release v2.2.1_2024-04-18
# - Builds images using the cloned get_phylomarkers GitHub repository
# - Based on rstudio/r-base:4.2.2-jammy (Ubuntu 22.04)
# - Runs 24 tests during the final image's build stage & sets ENV R_LIBS_SITE
# - Produces a lighter image by removing unnecessary R packages

# Base Image
FROM rstudio/r-base:4.2.2-jammy

# Metadata
LABEL authors="Pablo Vinuesa, Bruno Contreras Moreira" \
      keywords="bioinformatics, genomics, phylogenetics, phylogenomics, species tree, core-genome, pan-genome" \
      version="20240418" \
      description="Ubuntu 22.04 + Rstudio/r-base 4.2.2 based image of GET_PHYLOMARKERS" \
      summary="Runs GET_PHYLOMARKERS for phylogenomic analysis of microbial pan-genomes" \
      home="https://hub.docker.com/r/vinuesa/get_phylomarkers" \
      github="https://github.com/vinuesa/get_phylomarkers" \
      reference="PMID:29765358 <https://pubmed.ncbi.nlm.nih.gov/29765358/>" \
      license="GPLv3 <https://www.gnu.org/licenses/gpl-3.0.html>"

# Install required Linux tools and R packages
RUN apt update && apt install --no-install-recommends -y \
    software-properties-common dirmngr bash-completion bc build-essential \
    cpanminus curl gcc git default-jre libssl-dev make parallel wget \
    r-cran-ape r-cran-remotes r-cran-gplots r-cran-vioplot r-cran-plyr \
    r-cran-dplyr r-cran-ggplot2 r-cran-stringi r-cran-stringr r-cran-seqinr \
    python2.7 python2.7-dev \
    && apt clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && cpanm Term::ReadLine

# Clone get_phylomarkers and install dependencies
RUN git clone https://github.com/vinuesa/get_phylomarkers.git /get_phylomarkers \
    && Rscript /get_phylomarkers/install_kdetrees_from_github.R

# Set working directory
WORKDIR /get_phylomarkers

# Configure environment
ENV R_LIBS_SITE="/usr/local/lib/R/site-library:/usr/lib/R/site-library:/usr/lib/R/library:/opt/R/4.2.2/lib/R/library:/get_phylomarkers/lib/R" \
    LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"

# Copy required library and adjust permissions
RUN cp /get_phylomarkers/lib/libnw.so /usr/local/lib \
    && ldconfig \
    && chmod -R a+wr /get_phylomarkers/test_sequences

# Add version tag to image
ARG version
LABEL version=$version
RUN echo $version

# Create a user environment
RUN useradd --create-home --shell /bin/bash you
ENV USER=you
USER you

# Run get_phylomarkers tests on fully built image
RUN make clean && make test && make clean

# Set working directory for user
WORKDIR /home/you
ENV PATH="${PATH}:/get_phylomarkers"

# Start a Bash shell
CMD ["/bin/bash"]
