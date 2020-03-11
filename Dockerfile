FROM ubuntu:bionic

LABEL authors="Julien Neuhart <j.neuhart@thecodingmachine.com>, David Négrier <d.negrier@thecodingmachine.com>"

# Fixes some weird terminal issues such as broken clear / CTRL+L
#ENV TERM=linux

# Ensure apt doesn't ask questions when installing stuff
ENV DEBIAN_FRONTEND=noninteractive

ARG PHP_VERSION=7.3
ENV PHP_VERSION=$PHP_VERSION

# |--------------------------------------------------------------------------
# | Main PHP extensions
# |--------------------------------------------------------------------------
# |
# | Installs the main PHP extensions
# |

# Install php an other packages
RUN apt-get update \
    && apt-get install -y --no-install-recommends gnupg \
    && echo "deb http://ppa.launchpad.net/ondrej/php/ubuntu bionic main" > /etc/apt/sources.list.d/ondrej-php.list \
    && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 4F4EA0AAE5267A6C \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        nano \
        sudo \
        iproute2 \
        openssh-client \
        procps \
        unzip \
        ca-certificates \
        curl \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-json \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-readline \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc/*

# |--------------------------------------------------------------------------
# | User
# |--------------------------------------------------------------------------
# |
# | Define a default user with sudo rights.
# |

RUN useradd -ms /bin/bash docker && adduser docker sudo
# Users in the sudoers group can sudo as root without password.
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# |--------------------------------------------------------------------------
# | Default php.ini file
# |--------------------------------------------------------------------------
# |
# | For some reasons, the official image has a php.ini-production.cli file
# | but no php.ini-development.cli file. Let's create this one.
# |

RUN cp /usr/lib/php/${PHP_VERSION}/php.ini-development /usr/lib/php/${PHP_VERSION}/php.ini-development.cli && \
    sed -i 's/^disable_functions/;disable_functions/g' /usr/lib/php/${PHP_VERSION}/php.ini-development.cli && \
    sed -i 's/^memory_limit = .*/memory_limit = -1/g' /usr/lib/php/${PHP_VERSION}/php.ini-development.cli

#ADD https://raw.githubusercontent.com/php/php-src/PHP-${PHP_VERSION}/php.ini-production /usr/local/etc/php/php.ini-production
#ADD https://raw.githubusercontent.com/php/php-src/PHP-${PHP_VERSION}/php.ini-development /usr/local/etc/php/php.ini-development
#RUN chmod 644 /usr/local/etc/php/php.ini-*

ENV TEMPLATE_PHP_INI=development

# Let's remove the default CLI php.ini file (it will be copied from TEMPLATE_PHP_INI)
RUN rm /etc/php/${PHP_VERSION}/cli/php.ini

# |--------------------------------------------------------------------------
# | Composer
# |--------------------------------------------------------------------------
# |
# | Installs Composer to easily manage your PHP dependencies.
# |

#ENV COMPOSER_ALLOW_SUPERUSER 1

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=real_composer &&\
    chmod +x /usr/local/bin/real_composer

# TODO: utils.php in /usr/local/bin... bof!
COPY utils/utils.php /usr/local/bin/utils.php
COPY utils/composer_proxy.php /usr/local/bin/composer
COPY utils/generate_conf.php /usr/local/bin/generate_conf.php
COPY utils/setup_extensions.php /usr/local/bin/setup_extensions.php

# |--------------------------------------------------------------------------
# | Default PHP extensions to be enabled
# | By default, enable all the extensions that are enabled on a base Ubuntu install
# |--------------------------------------------------------------------------
ENV PHP_EXTENSION_CALENDAR=1 \
    PHP_EXTENSION_CTYPE=1 \
    PHP_EXTENSION_CURL=1 \
    PHP_EXTENSION_DOM=1 \
    PHP_EXTENSION_EXIF=1 \
    PHP_EXTENSION_FILEINFO=1 \
    PHP_EXTENSION_FTP=1 \
    PHP_EXTENSION_GETTEXT=1 \
    PHP_EXTENSION_ICONV=1 \
    PHP_EXTENSION_JSON=1 \
    PHP_EXTENSION_MBSTRING=1 \
    PHP_EXTENSION_OPCACHE=1 \
    PHP_EXTENSION_PDO=1 \
    PHP_EXTENSION_PHAR=1 \
    PHP_EXTENSION_POSIX=1 \
    PHP_EXTENSION_READLINE=1 \
    PHP_EXTENSION_SHMOP=1 \
    PHP_EXTENSION_SIMPLEXML=1 \
    PHP_EXTENSION_SOCKETS=1 \
    PHP_EXTENSION_SYSVMSG=1 \
    PHP_EXTENSION_SYSVSEM=1 \
    PHP_EXTENSION_SYSVSHM=1 \
    PHP_EXTENSION_TOKENIZER=1 \
    PHP_EXTENSION_WDDX=1 \
    PHP_EXTENSION_XML=1 \
    PHP_EXTENSION_XMLREADER=1 \
    PHP_EXTENSION_XMLWRITER=1 \
    PHP_EXTENSION_XSL=1 \
    PHP_EXTENSION_ZIP=1

# |--------------------------------------------------------------------------
# | prestissimo
# |--------------------------------------------------------------------------
# |
# | Installs Prestissimo to improve Composer download performance.
# |

USER docker
RUN composer global require hirak/prestissimo && \
    composer global require bamarni/symfony-console-autocomplete && \
    rm -rf ~/.composer/cache

USER root


ENV APACHE_CONFDIR /etc/apache2
ENV APACHE_ENVVARS $APACHE_CONFDIR/envvars

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends apache2 libapache2-mod-php${PHP_VERSION}; \
	rm -rf /var/lib/apt/lists/*; \
	\
# generically convert lines like
#   export APACHE_RUN_USER=www-data
# into
#   : ${APACHE_RUN_USER:=www-data}
#   export APACHE_RUN_USER
# so that they can be overridden at runtime ("-e APACHE_RUN_USER=...")
	sed -ri 's/^export ([^=]+)=(.*)$/: ${\1:=\2}\nexport \1/' "$APACHE_ENVVARS"; \
	\
# setup directories and permissions
	. "$APACHE_ENVVARS"; \
	for dir in \
		"$APACHE_LOCK_DIR" \
		"$APACHE_RUN_DIR" \
		"$APACHE_LOG_DIR" \
	; do \
		rm -rvf "$dir"; \
		mkdir -p "$dir"; \
		chown "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$dir"; \
# allow running as an arbitrary user (https://github.com/docker-library/php/issues/743)
		chmod 777 "$dir"; \
	done; \
	\
# delete the "index.html" that installing Apache drops in here
	rm -rvf /var/www/html/*; \
	\
# logs should go to stdout / stderr
	ln -sfT /dev/stderr "$APACHE_LOG_DIR/error.log"; \
	ln -sfT /dev/stdout "$APACHE_LOG_DIR/access.log"; \
	ln -sfT /dev/stdout "$APACHE_LOG_DIR/other_vhosts_access.log"; \
	chown -R --no-dereference "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$APACHE_LOG_DIR"

# Apache + PHP requires preforking Apache for best results
RUN a2dismod mpm_event && a2enmod mpm_prefork

# PHP files should be handled by PHP, and should be preferred over any other file type
COPY utils/apache-docker-php.conf /etc/apache2/conf-available/docker-php.conf

RUN a2enconf docker-php

ENV PHP_EXTRA_BUILD_DEPS apache2-dev
ENV PHP_EXTRA_CONFIGURE_ARGS --with-apxs2 --disable-cgi

# https://httpd.apache.org/docs/2.4/stopping.html#gracefulstop
STOPSIGNAL SIGWINCH

COPY utils/apache2-foreground /usr/local/bin/

EXPOSE 80

ENV APACHE_DOCUMENT_ROOT=

RUN sed -ri -e 's!/var/www/html!${ABSOLUTE_APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/!${ABSOLUTE_APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Let's remove the default Apache php.ini file (it will be copied from TEMPLATE_PHP_INI)
RUN rm /etc/php/${PHP_VERSION}/apache2/php.ini

# |--------------------------------------------------------------------------
# | Apache mod_rewrite
# |--------------------------------------------------------------------------
# |
# | Enables Apache mod_rewrite.
# |

RUN a2enmod rewrite








RUN chown docker:docker /var/www/html
WORKDIR /var/www/html


# |--------------------------------------------------------------------------
# | PATH updating
# |--------------------------------------------------------------------------
# |
# | Let's add ./vendor/bin to the PATH (utility function to use Composer bin easily)
# |
ENV PATH="$PATH:./vendor/bin:~/.composer/vendor/bin"
RUN sed -i 's#/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin#/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:./vendor/bin:~/.composer/vendor/bin#g' /etc/sudoers

USER docker
# |--------------------------------------------------------------------------
# | SSH client
# |--------------------------------------------------------------------------
# |
# | Let's set-up the SSH client (for connections to private git repositories)
# | We create an empty known_host file and we launch the ssh-agent
# |

RUN mkdir ~/.ssh && touch ~/.ssh/known_hosts && chmod 644 ~/.ssh/known_hosts && eval $(ssh-agent -s)


# |--------------------------------------------------------------------------
# | .bashrc updating
# |--------------------------------------------------------------------------
# |
# | Let's update the .bashrc to add nice aliases
# |

RUN echo 'eval "$(symfony-autocomplete)"' > ~/.bash_profile

RUN { \
        echo "alias ls='ls --color=auto'"; \
        echo "alias ll='ls --color=auto -alF'"; \
        echo "alias la='ls --color=auto -A'"; \
        echo "alias l='ls --color=auto -CF'"; \
    } >> ~/.bashrc

USER root

# |--------------------------------------------------------------------------
# | NodeJS
# |--------------------------------------------------------------------------
# |
# | NodeJS path registration (if we install NodeJS, this is useful).
# |
ENV PATH="$PATH:./node_modules/.bin"
RUN sed -i 's#/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin#/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:./node_modules/.bin#g' /etc/sudoers

# |--------------------------------------------------------------------------
# | Entrypoint
# |--------------------------------------------------------------------------
# |
# | Defines the entrypoint.
# |

ENV IMAGE_VARIANT=apache

# Add Tini (to be able to stop the container with ctrl-c).
# See: https://github.com/krallin/tini
ENV TINI_VERSION v0.16.1
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

COPY utils/generate_cron.php /usr/local/bin/generate_cron.php
COPY utils/startup_commands.php /usr/local/bin/startup_commands.php

COPY utils/enable_apache_mods.php /usr/local/bin/enable_apache_mods.php
COPY utils/apache-expose-envvars.sh /usr/local/bin/apache-expose-envvars.sh

COPY utils/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY utils/docker-entrypoint-as-root.sh /usr/local/bin/docker-entrypoint-as-root.sh

COPY extensions/ /usr/local/lib/thecodingmachine-php/extensions
RUN ln -s ${PHP_VERSION} /usr/local/lib/thecodingmachine-php/extensions/current

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]


# Let's register a servername to remove the message "apache2: Could not reliably determine the server's fully qualified domain name, using 172.17.0.2. Set the 'ServerName' directive globally to suppress this message"
RUN echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf
RUN a2enconf servername

CMD ["apache2-foreground"]

# |--------------------------------------------------------------------------
# | Entrypoint
# |--------------------------------------------------------------------------
# |
# | Defines Apache user. By default, we switch this to "docker" user.
# | This way, no problem to write from Apache in the current working directory.
# | Important! This should be changed back to www-data in production.
# |

ENV APACHE_RUN_USER=docker \
    APACHE_RUN_GROUP=docker




RUN touch /etc/php/${PHP_VERSION}/mods-available/generated_conf.ini && ln -s /etc/php/${PHP_VERSION}/mods-available/generated_conf.ini /etc/php/${PHP_VERSION}/cli/conf.d/generated_conf.ini


RUN ln -s /etc/php/${PHP_VERSION}/mods-available/generated_conf.ini /etc/php/${PHP_VERSION}/apache2/conf.d/generated_conf.ini




USER docker

COPY utils/install_selected_extensions.php /usr/local/bin/install_selected_extensions.php
COPY utils/install_selected_extensions.sh /usr/local/bin/install_selected_extensions.sh

ONBUILD ARG PHP_EXTENSIONS
ONBUILD ENV PHP_EXTENSIONS="$PHP_EXTENSIONS"
ONBUILD RUN sudo -E PHP_EXTENSIONS="$PHP_EXTENSIONS" /usr/local/bin/install_selected_extensions.sh

# |--------------------------------------------------------------------------
# | Supercronic
# |--------------------------------------------------------------------------
# |
# | Supercronic is a drop-in replacement for cron (for containers).
# |
ENV SUPERCRONIC_OPTIONS=

ONBUILD ARG INSTALL_CRON
ONBUILD RUN if [ -n "$INSTALL_CRON" ]; then \
 SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.1.9/supercronic-linux-amd64 \
 && SUPERCRONIC=supercronic-linux-amd64 \
 && SUPERCRONIC_SHA1SUM=5ddf8ea26b56d4a7ff6faecdd8966610d5cb9d85 \
 && curl -fsSLO "$SUPERCRONIC_URL" \
 && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
 && chmod +x "$SUPERCRONIC" \
 && sudo mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
 && sudo ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic; \
 fi;


# |--------------------------------------------------------------------------
# | NodeJS
# |--------------------------------------------------------------------------
# |
# | Installs NodeJS and npm. The later will allow you to easily manage
# | your frontend dependencies.
# | Also installs yarn. It provides some nice improvements over npm.
# |
ONBUILD ARG NODE_VERSION
ONBUILD RUN if [ -n "$NODE_VERSION" ]; then \
    sudo apt-get update && \
    sudo apt-get install -y --no-install-recommends gnupg && \
    curl -sL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo bash - && \
    sudo apt-get update && \
    sudo apt-get install -y --no-install-recommends nodejs && \
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add - && \
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list && \
    sudo apt-get update && \
    sudo apt-get install -y --no-install-recommends yarn; \
    fi;

ARG INSTALL_CRON=1
ARG INSTALL_COMPOSER=1

LABEL authors="Julien Neuhart <j.neuhart@thecodingmachine.com>, David Négrier <d.negrier@thecodingmachine.com>"

# |--------------------------------------------------------------------------
# | Main PHP extensions
# |--------------------------------------------------------------------------
# |
# | Installs the main PHP extensions
# |

USER root
RUN cd /usr/local/lib/thecodingmachine-php/extensions/current/ && ./install_all.sh && ./disable_all.sh
USER docker

# |--------------------------------------------------------------------------
# | Default PHP extensions to be enabled (in addition to the one declared in Slim build)
# |--------------------------------------------------------------------------
ENV PHP_EXTENSION_APCU=1 \
    PHP_EXTENSION_MYSQLI=1 \
    PHP_EXTENSION_PDO_MYSQL=1 \
    PHP_EXTENSION_IGBINARY=1 \
    PHP_EXTENSION_REDIS=1 \
    PHP_EXTENSION_SOAP=1
