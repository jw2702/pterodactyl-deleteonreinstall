/you wish to continue?/a\
                {/* blueprintframework:deleteonreinstall:start */}\
                <p css={tw`mt-4 -mb-2 bg-gray-700 p-3 rounded`}>\
                    <label htmlFor={'reinstall_truncate'} css={tw`text-base flex items-center cursor-pointer`}>\
                        <Input\
                            type={'checkbox'}\
                            css={tw`text-red-500! w-5! h-5! mr-2`}\
                            id={'reinstall_truncate'}\
                            value={'true'}\
                            checked={truncate}\
                            onChange={() => setTruncate((s) => !s)}\
                        />\
                        Delete all files before reinstalling.\
                    </label>\
                </p>\
                {/* blueprintframework:deleteonreinstall:end */}
