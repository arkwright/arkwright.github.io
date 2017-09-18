mkdir -p png

for image in $( ls *.png ); do
  filename=$(basename "$image" .png)

  convert $filename.png -colorspace Gray -scale "100%" -auto-gamma -auto-level -brightness-contrast 10x10 $filename.bmp

  rm $filename.svg 2> /dev/null
  potrace -s -H 400pt -t 10 -z black -C "#444444" --tight $filename.bmp

  rm $filename.bmp 2> /dev/null

  echo "Coverted $filename.svg"
done

mv *.png png/
