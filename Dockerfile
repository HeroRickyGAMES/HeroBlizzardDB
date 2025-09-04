# Estágio 1: Build - Usamos a imagem oficial do Dart para compilar a aplicação
FROM dart:stable AS build

WORKDIR /app

# Copia os arquivos de dependência e as instala
COPY pubspec.* ./
RUN dart pub get

# Copia todo o resto do código do projeto
COPY . .

# Compila a aplicação em um executável nativo e otimizado
RUN dart compile exe bin/server.dart -o bin/server

# Estágio 2: Runtime - Usamos uma imagem mínima para rodar o executável
FROM scratch

# Copia o runtime AOT do estágio de build
COPY --from=build /runtime/ /

# Copia o executável compilado do estágio de build
COPY --from=build /app/bin/server /app/bin/server

# CORREÇÃO: Define o diretório de trabalho para a aplicação
WORKDIR /app

# Copia a pasta 'public' para o local correto (relativo ao WORKDIR)
COPY --from=build /app/public ./public/

# Expõe a porta que o servidor vai usar
EXPOSE 8080

# Comando para iniciar o servidor (agora relativo ao WORKDIR)
CMD ["bin/server"]