## Dockerfile version 2024-04-18, associated with GitHub release v2.2.1_2024-04-18
# - build images using as context the cloned get_phylomarkers GitHub repository
#     based on latest ubuntu (jammy) and r-base (4.2.2)
# - runs 24 tests during the final image's build stage & sets ENV R_LIBS_SITE
# - produces a significantly lighter image, as several unnecessary R packages were removed,
#     and remotes replaces the much heavier devtools

# Check versions: https://hub.docker.com/_/ubuntu
FROM ubuntu:latest

#Check versions and compatibility with ubuntu releases at https://github.com/rstudio/r-docker
FROM rstudio/r-base:4.2.2-jammy

LABEL authors="Pablo Vinuesa <https://www.ccg.unam.mx/~vinuesa/> and Bruno Contreras Moreira <https://www.eead.csic.es/compbio/>"
LABEL keywods="bioinformatics, genomics, phylogenetics, phylogenomics, species tree, core-genome, pan-genome, maximum likelihood, parsimony, population genetics, molecular clock, Docker image, pipeline"
LABEL version="20240418"
LABEL description="Ubuntu 22.04 + Rstudio/r-base 4.2.2 based image of GET_PHYLOMARKERS"
LABEL summary="This image runs GET_PHYLOMARKERS for advanced and versatile phylogenomic analysis of microbial pan-genomes"
LABEL home="<https://hub.docker.com/r/vinuesa/get_phylomarkers>"
LABEL get_phylomarkers.github.home="<https://github.com/vinuesa/get_phylomarkers>"
LABEL get_phylomarkers.reference="PMID:29765358 <https://pubmed.ncbi.nlm.nih.gov/29765358/"
LABEL license="GPLv3 <https://www.gnu.org/licenses/gpl-3.0.html>"

## Install required linux tools
RUN apt update && apt install --no-install-recommends -y \
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
wget \
&& apt clean && apt purge && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && cpanm Term::ReadLine

## mkdir get_phylomarkes in /, copy all contents into it; make it the working directory & install required R packages
# update indices
RUN apt update -qq 
RUN apt install --no-install-recommends software-properties-common dirmngr
RUN wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | sudo tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc
RUN add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"
RUN apt install --no-install-recommends -y r-base
#RUN add-apt-repository ppa:c2d4u.team/c2d4u4.0+
RUN apt install --no-install-recommends -y \
r-cran-ape \
r-cran-remotes \
r-cran-distory \
r-cran-hgm \
r-cran-ggplot2 \
r-cran-gplots \
r-cran-vioplot \
r-cran-plyr \
r-cran-dplyr \
r-cran-ggplot2 \
r-cran-stringi \
r-cran-stringr \
r-cran-seqinr \
&& apt clean && apt purge && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN git clone https://github.com/TT1972/get_phylomarkers.git
WORKDIR /get_phylomarkers 

# need to install kdetrees from the github repo, as it was removed from CRAN
# RUN Rscript install_kdetrees_from_github.R

# Copy local kdetrees source tarball into the image
COPY kdetrees_*.tar.gz /tmp/

# Install kdetrees from tarball
RUN R CMD INSTALL /tmp/kdetrees_*.tar.gz

# set R paths; run R -q -e '.libPaths()' on Linux (Ubuntu) host, and docker container;
ENV R_LIBS_SITE=/usr/local/lib/R/site-library:/usr/lib/R/site-library/:/usr/lib/R/library:/opt/R/4.2.2/lib/R/library:/get_phylomarkers/lib/R

## python2.7 required by paup; python2.7-dev to get libpython2.7.so.1.0
#   add python2.7 at this stage, as rstudio/r-base:3.6.3-bionic seems to overwrite�python2.7 in the first RUN apt above
#   this seems the only way to get python2.7 and python2.7-dev in newer ubuntu:18.04 images
#   as otherwise only python 3.6 gets installed.
#  Copy libnw required by newick-utils to /usr/local/lib and export LD_LIBRARY_PATH for ldconfig
RUN apt update && apt install --no-install-recommends -y python2.7 python2.7-dev \
&& apt clean && apt purge && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
&& cp /get_phylomarkers/lib/libnw.so /usr/local/lib \
&& export LD_LIBRARY_PATH=/usr/local/lib \
&& ldconfig \
&& chmod -R a+wr /get_phylomarkers/test_sequences

## add version tag to image
ARG version
LABEL version=$version
RUN echo $version

## Prepare USER env
RUN useradd --create-home --shell /bin/bash you
# set USER=you for pgrep calls, as the only ENV-VARS documented to be set are HOME HOSTNAME PATH and TERM
#  https://docs.docker.com/engine/reference/run/#env-environment-variables
ENV USER=you
USER you

# run get_phylomarkers tests on fully built image
RUN make clean && make test && make clean

WORKDIR /home/you
ENV PATH="${PATH}:/get_phylomarkers"

# make sure the user gets a Bash shell and some help to get started
CMD ["/bin/bash"]

## USAGE:
# 1. Copy test data from /get_phylomarkers/test_sequences
# - open a terminal on your post and type: 
# $ cd && mkdir -p ~/data/genomes/test_sequences

# 2. Assuming that you have your core_genome and/or pan_genome data availabe in ~/data/genomes/test_sequences 
# bind mount that host directory on the container instance under /home/you/data with the following command:
# $ docker run -it --rm -v ~/data/genomes/test_sequences:/home/you/data vinuesa/get_phylomarkers:latest /bin/bash

# Copy the test sequences to your data directory
# $ cp -r /get_phylomarkers/test_sequences/core_genome ~/data/
# $ cp -r /get_phylomarkers/test_sequences/pan_genome ~/data/
# $ cd ~/data 

## Functional testing
# $ cd ~/data/core_genome
# $ ls
# $ run_get_phylomarkers_pipeline.sh -h
# $ run_get_phylomarkers_pipeline.sh -R 1 -t DNA
# $ cd ~/data/pan_genome
# $ estimate_pangenome_phylogenies.sh -f pangenome_matrix_t0.fasta -r 1 -S UFBoot

## Thorough functional testing (9 tests calling the two main scripts) can also be run automatically as follows,
#   assuming that you have copied the core_genome and pan_genome test sequences to the data directory, as indicated above.
# $ cd && run_test_suite.sh /home/you/data
