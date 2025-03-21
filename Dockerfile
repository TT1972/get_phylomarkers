## Dockerfile version 2025-03-21, associated with GitHub release v2.2.1_2024-04-18
# - Builds images using the cloned get_phylomarkers GitHub repository
# - Based on Ubuntu (jammy) and r-base (4.2.2)
# - Runs 24 tests during the final image's build stage & sets ENV R_LIBS_SITE
# - Produces a lighter image by removing unnecessary R packages

# Base Images
FROM ubuntu:latest
FROM rstudio/r-base:4.2.2-jammy

# Metadata
LABEL authors="Pablo Vinuesa <https://www.ccg.unam.mx/~vinuesa/> and Bruno Contreras Moreira <https://www.eead.csic.es/compbio/>"
LABEL keywords="bioinformatics, genomics, phylogenetics, phylogenomics, species tree, core-genome, pan-genome"
LABEL version="20240418"
LABEL description="Ubuntu 22.04 + Rstudio/r-base 4.2.2 based image of GET_PHYLOMARKERS"
LABEL summary="Runs GET_PHYLOMARKERS for phylogenomic analysis of microbial pan-genomes"
LABEL home="<https://hub.docker.com/r/vinuesa/get_phylomarkers>"
LABEL github="<https://github.com/vinuesa/get_phylomarkers>"
LABEL reference="PMID:29765358 <https://pubmed.ncbi.nlm.nih.gov/29765358/>"
LABEL license="GPLv3 <https://www.gnu.org/licenses/gpl-3.0.html>"

# Install required Linux tools
RUN apt update && \
    apt install --no-install-recommends -y \
        software-properties-common \
        dirmngr \
        bash-completion \
        bc \
        build-essential \
        cpanminus \
        curl \
        gcc \
        git \
        default-jre \
        libssl-dev \
        make \
        parallel \
        wget && \
    apt clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    cpanm Term::ReadLine

# Install R and required packages
RUN apt update -qq && \
    apt install --no-install-recommends -y software-properties-common dirmngr && \
    wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | \
    sudo tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc && \
    add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" && \
    apt install --no-install-recommends -y r-base && \
    apt install --no-install-recommends -y \
        r-cran-ape \
        r-cran-remotes \
        r-cran-gplots \
        r-cran-vioplot \
        r-cran-plyr \
        r-cran-dplyr \
        r-cran-ggplot2 \
        r-cran-stringi \
        r-cran-stringr \
        r-cran-seqinr && \
    apt clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Clone get_phylomarkers and set working directory
RUN git clone https://github.com/vinuesa/get_phylomarkers.git
WORKDIR /get_phylomarkers

# Install kdetrees from GitHub
RUN Rscript install_kdetrees_from_github.R

# Set R library paths
ENV R_LIBS_SITE="/usr/local/lib/R/site-library:/usr/lib/R/site-library:/usr/lib/R/library:/opt/R/4.2.2/lib/R/library:/get_phylomarkers/lib/R"

# Install Python 2.7 for PAUP and configure libraries
RUN apt update && \
    apt install --no-install-recommends -y python2.7 python2.7-dev && \
    apt clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN cp /get_phylomarkers/lib/libnw.so /usr/local/lib && \
    export LD_LIBRARY_PATH=/usr/local/lib && \
    ldconfig

RUN chmod -R a+wr /get_phylomarkers/test_sequences

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
