-- Restrict public bucket listing on memory-photos
CREATE POLICY "Restrict bucket listing" 
ON storage.objects 
FOR SELECT 
TO public 
USING (bucket_id = 'memory-photos' AND (auth.role() = 'authenticated' OR auth.uid() IS NOT NULL));