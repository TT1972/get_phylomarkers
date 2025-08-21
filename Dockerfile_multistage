## ------------------------------------------------------
## Stage 1: Builder
## ------------------------------------------------------
FROM rstudio/r-base:4.2.2-jammy AS builder

LABEL stage="builder"

# Install build & test dependencies
RUN apt-get update && apt-get install --no-install-recommends -y \
    software-properties-common dirmngr bash-completion bc build-essential \
    cpanminus curl gcc git default-jre libssl-dev make parallel wget \
    python2.7 python2.7-dev \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Perl module
RUN cpanm Term::ReadLine

# Install required R packages
RUN apt-get update && apt-get install --no-install-recommends -y \
    r-cran-ape r-cran-remotes r-cran-gplots \
    r-cran-vioplot r-cran-plyr r-cran-dplyr \
    r-cran-ggplot2 r-cran-stringi r-cran-stringr r-cran-seqinr \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Clone source repo
RUN git clone https://github.com/TT1972/get_phylomarkers.git /get_phylomarkers
WORKDIR /get_phylomarkers

# Install kdetrees from GitHub
RUN Rscript install_kdetrees_from_github.R

# Copy required library file
RUN cp /get_phylomarkers/lib/libnw.so /usr/local/lib && ldconfig

# Ensure tests can run
RUN chmod -R a+wr /get_phylomarkers/test_sequences

# Run build tests
RUN make clean && make test && make clean

## ------------------------------------------------------
## Stage 2: Final runtime image
## ------------------------------------------------------
FROM rstudio/r-base:4.2.2-jammy

LABEL authors="Pablo Vinuesa <https://www.ccg.unam.mx/~vinuesa/>, Bruno Contreras Moreira <https://www.eead.csic.es/compbio/>"
LABEL description="Lightweight runtime image of GET_PHYLOMARKERS (Ubuntu 22.04 + R 4.2.2)"
LABEL license="GPLv3 https://www.gnu.org/licenses/gpl-3.0.html"

# Minimal runtime dependencies
RUN apt-get update && apt-get install --no-install-recommends -y \
    default-jre python2.7 \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy built repo from builder
COPY --from=builder /get_phylomarkers /get_phylomarkers
COPY --from=builder /usr/local/lib/libnw.so /usr/local/lib/libnw.so

# Configure R libraries
ENV R_LIBS_SITE=/usr/local/lib/R/site-library:/usr/lib/R/site-library:/usr/lib/R/library:/opt/R/4.2.2/lib/R/library:/get_phylomarkers/lib/R

# Create non-root user
RUN useradd --create-home --shell /bin/bash you
USER you

# Final PATH
WORKDIR /home/you
ENV PATH="${PATH}:/get_phylomarkers"

# Default shell
CMD ["/bin/bash"]
