# brew install imagemagick
# brew install potrace

mkdir -p png

for image in $( ls *.png ); do
  filename=$(basename "$image" .png)

  convert $filename.png -type Grayscale -scale "100%" -auto-gamma -auto-level -brightness-contrast 40x40 $filename.bmp

  rm $filename.svg 2> /dev/null
  potrace -s -H 400pt -t 10 -z black -C "#444444" --tight $filename.bmp

  rm $filename.bmp 2> /dev/null

  echo "Coverted $filename.svg"
done

mv *.png png/
