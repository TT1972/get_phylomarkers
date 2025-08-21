## Dockerfile version 2024-04-18, associated with GitHub release v2.2.1_2024-04-18
# - Based on ubuntu jammy with r-base 4.2.2
# - Runs tests during final image build & sets ENV R_LIBS_SITE
# - Produces a lighter image by installing only required R packages

FROM rstudio/r-base:4.2.2-jammy

LABEL authors="Pablo Vinuesa <https://www.ccg.unam.mx/~vinuesa/>, Bruno Contreras Moreira <https://www.eead.csic.es/compbio/>"
LABEL keywords="bioinformatics, genomics, phylogenetics, phylogenomics, species tree, core-genome, pan-genome, maximum likelihood, parsimony, population genetics, molecular clock, Docker image, pipeline"
LABEL version="20240418"
LABEL description="Ubuntu 22.04 + Rstudio/r-base 4.2.2 based image of GET_PHYLOMARKERS"
LABEL summary="This image runs GET_PHYLOMARKERS for advanced and versatile phylogenomic analysis of microbial pan-genomes"
LABEL home="https://hub.docker.com/r/vinuesa/get_phylomarkers"
LABEL get_phylomarkers.github.home="https://github.com/vinuesa/get_phylomarkers"
LABEL get_phylomarkers.reference="PMID:29765358 https://pubmed.ncbi.nlm.nih.gov/29765358/"
LABEL license="GPLv3 https://www.gnu.org/licenses/gpl-3.0.html"

# Install base dependencies
RUN apt-get update && apt-get install --no-install-recommends -y \
    software-properties-common dirmngr bash-completion bc build-essential \
    cpanminus curl gcc git default-jre libssl-dev make parallel wget \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Perl module separately
RUN cpanm Term::ReadLine

# Install R packages (split into smaller steps)
RUN apt-get update && apt-get install --no-install-recommends -y \
    r-cran-ape r-cran-remotes r-cran-gplots \
 && apt-get install --no-install-recommends -y \
    r-cran-vioplot r-cran-plyr r-cran-dplyr \
 && apt-get install --no-install-recommends -y \
    r-cran-ggplot2 r-cran-stringi r-cran-stringr r-cran-seqinr \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Clone repository
RUN git clone https://github.com/TT1972/get_phylomarkers.git
WORKDIR /get_phylomarkers

# Install kdetrees from GitHub (removed from CRAN)
RUN Rscript install_kdetrees_from_github.R

# Set R paths
ENV R_LIBS_SITE=/usr/local/lib/R/site-library:/usr/lib/R/site-library:/usr/lib/R/library:/opt/R/4.2.2/lib/R/library:/get_phylomarkers/lib/R

# Install Python 2.7 (required by paup) + dependencies
RUN apt-get update && apt-get install --no-install-recommends -y \
    python2.7 python2.7-dev \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && cp /get_phylomarkers/lib/libnw.so /usr/local/lib \
 && ldconfig \
 && chmod -R a+wr /get_phylomarkers/test_sequences

# Add version tag to image
ARG version
LABEL version=$version
RUN echo $version

# Prepare user environment
RUN useradd --create-home --shell /bin/bash you
ENV USER=you
USER you

# Run tests on fully built image
RUN make clean && make test && make clean

# Final environment setup
WORKDIR /home/you
ENV PATH="${PATH}:/get_phylomarkers"

# Default shell
CMD ["/bin/bash"]
