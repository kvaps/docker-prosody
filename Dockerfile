FROM centos:centos6
MAINTAINER kvaps <kvapss@gmail.com>
ENV REFRESHED_AT 2015-09-17

RUN yum -y update
RUN yum -y install epel-release 

# Install additional soft
RUN yum -y install mysql-server supervisor fail2ban dhclient lua-ldap mercurial tar rsyslog dhclient

# Install build-essentials and lua-modules
RUN yum -y install gcc lua-devel openssl-devel libidn-devel lua-expat lua-socket lua-filesystem lua-sec lua-dbi

ENV LUACPATH="/usr/lib64/lua/5.1"
ENV LIBDIR="-L/usr/lib64"

# Install lua-zlib module
RUN curl https://codeload.github.com/brimworks/lua-zlib/tar.gz/v0.4 | tar xzv -C /usr/src/
WORKDIR /usr/src/lua-zlib-0.4/
RUN make linux
RUN make install

# Install lua-bitop module
RUN curl http://bitop.luajit.org/download/LuaBitOp-1.0.2.tar.gz | tar xzv -C /usr/src/
WORKDIR /usr/src/LuaBitOp-1.0.2
RUN make
RUN make install

RUN yum -y install git 

#Install Metronome
RUN git clone https://github.com/maranda/metronome.git /usr/src/metronome
WORKDIR /usr/src/metronome
RUN ./configure --prefix=
RUN make
RUN make install
RUN useradd -r -s /sbin/nologin -d /var/lib/metronome metronome
RUN mkdir /var/log/metronome/
RUN mkdir /var/run/metronome/
RUN chown metronome:metronome /var/lib/metronome/
RUN chown metronome:metronome /var/log/metronome/
RUN chown metronome:metronome /var/run/metronome/

#Install Prosody-modules
RUN hg clone http://hg.prosody.im/prosody-modules/ /usr/src/prosody-modules
RUN cp -r /usr/src/prosody-modules /usr/src/metronome-modules
RUN find /usr/src/metronome-modules -type f -print0 | xargs -0 sed -i 's/prosody/metronome/g'
RUN ln -s /usr/src/metronome-modules/mod_lib_ldap/ldap.lib.lua /lib/metronome/modules/ldap.lib.lua

RUN yum -y install lua-event

# Add config and setup script, run it
ADD wrappers/* /bin/
ADD metronome.cfg.lua /etc/metronome/metronome.cfg.lua
ADD kolabgr.lua /etc/metronome/kolabgr.lua
ADD groups.txt /etc/metronome/groups.txt
ADD settings.ini /etc/settings.ini
ADD setup.sh /bin/setup.sh
ENTRYPOINT ["/bin/setup.sh", "run"]
 
WORKDIR /root


VOLUME ["/data"]

# 5000/tcp: mod_proxy65
# 5222/tcp: client to server
# 5269/tcp: server to server 
# 5280/tcp: BOSH
# 5281/tcp: Secure BOSH
EXPOSE 5000 5222 5269 5280 5281
